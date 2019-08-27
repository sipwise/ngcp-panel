package NGCP::Panel::Role::API::CFDestinationSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Form;

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "subscriber") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFDestinationSetSubAPI", $c);
    } elsif($c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFDestinationSetSubAPI", $c);
    } else {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFDestinationSetAPI", $c);
    }
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;
    my @destinations;
    for my $dest ($item->voip_cf_destinations->all) {
        my ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($dest->destination);
        my $deflated;
        if($d eq "uri") {
            $deflated = NGCP::Panel::Utils::Subscriber::uri_deflate($c, $duri, $item->subscriber->voip_subscriber);
            $d = $dest->destination;
        }
        my $destelem = {$dest->get_inflated_columns,
                destination => $dest->destination,
                $deflated ? (simple_destination => $deflated) : (),
            };
        delete @{$destelem}{'id', 'destination_set_id'};
        push @destinations, $destelem;
    }
    $resource{destinations} = \@destinations;

    my $b_subs_id = $item->subscriber->voip_subscriber->id;
    $resource{subscriber_id} = $b_subs_id;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_destination_sets');
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_cf_destination_sets')
            ->search_rs({
                    'reseller_id' => $reseller_id,
                } , {
                    join => {'subscriber' => {'contract' => 'contact'} },
                });
    } elsif($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_destination_sets')
            ->search_rs({
                    'subscriber_id' => $c->user->id,
                });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );
    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    }


    if (! exists $resource->{destinations} ) {
        $resource->{destinations} = [];
    }
    if(!$self->check_destinations($c, $resource)){
        return;
    }

    my $b_subscriber = $schema->resultset('voip_subscribers')->find($resource->{subscriber_id});
    unless ($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        return;
    }

    try {
        my $primary_nr_rs = $b_subscriber->primary_number;
        my $number;
        if ($primary_nr_rs) {
            $number = $primary_nr_rs->cc . ($primary_nr_rs->ac //'') . $primary_nr_rs->sn;
        } else {
            $number = ''
        }
        my $domain = $subscriber->domain->domain // '';

        $item->update({
                name => $resource->{name},
                subscriber_id => $subscriber->id,
            })->discard_changes;
        my $old_aa = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($item);
        $item->voip_cf_destinations->delete;
        for my $d ( @{$resource->{destinations}} ) {
            delete $d->{destination_set_id};
            delete $d->{simple_destination};
            $d->{destination} = NGCP::Panel::Utils::Subscriber::field_to_destination(
                    destination => $d->{destination},
                    number => $number,
                    domain => $domain,
                    uri => $d->{destination},
                );
            $item->create_related("voip_cf_destinations", $d);
        }
        $item->discard_changes;
        my $new_aa = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($item);
        foreach ($item->voip_cf_mappings->all) {
            NGCP::Panel::Utils::Subscriber::check_cf_ivr( # one event per affected mapping
                c => $c, schema => $schema,
                subscriber => $item->subscriber->voip_subscriber,
                old_aa => $old_aa,
                new_aa => $new_aa,
            );
        }
    } catch($e) {
        $c->log->error("failed to create cfdestinationset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfdestinationset.");
        return;
    };

    return $item;
}

sub check_destinations{
    my($self,$c,$resource) = @_;
    if (ref $resource->{destinations} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'destinations'. Must be an array.");
        return;
    }
    for my $d (@{ $resource->{destinations} }) {
        if (exists $d->{timeout} && ! is_int($d->{timeout})) {
            $c->log->error("Invalid timeout for the destination '".$c->qs($d->{destination})."'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid timeout for the destination '".$c->qs($d->{destination})."'");
            return;
        }
        if (exists $d->{priority} && ! is_int($d->{priority})) {
            $c->log->error("Invalid priority for the destination '".$c->qs($d->{destination})."'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid priority for the destination '".$c->qs($d->{destination})."'");
            return;
        }
        if (defined $d->{announcement_id}) {
        #todo: I think that user expects that put and get will be the same
            if(('customhours' ne $d->{destination}) && ('sip:custom-hours@app.local' ne $d->{destination}) ){
                $c->log->error("Invalid parameter 'announcement_id' for the destination '".$c->qs($d->{destination})."'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid parameter 'announcement_id' for the destination '".$c->qs($d->{destination})."'");
                return;
            }elsif(! is_int($d->{announcement_id})){
                $c->log->error("Invalid announcement_id");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid announcement_id");
                return;
            }elsif(! $c->model('DB')->resultset('voip_sound_handles')->search_rs({
               'me.id' => $d->{announcement_id},
               'group.name' => 'custom_announcements',
            },{
                'join' => 'group',
            })->first() ){
                $c->log->error("Unknown announcement_id: ".$d->{announcement_id});
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Unknown announcement_id:".$d->{announcement_id});
                return;
            }
        }
    }
    return 1;
}
1;
# vim: set tabstop=4 expandtab:
