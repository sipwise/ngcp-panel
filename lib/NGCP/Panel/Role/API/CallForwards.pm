package NGCP::Panel::Role::API::CallForwards;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::CFSimpleAPI;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::CFSimpleAPI->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;
    my $rwr_form = $self->get_form($c, "rules");
    
    my $prov_subs = $item->provisioning_voip_subscriber;

    die "no provisioning_voip_subscriber" unless $prov_subs;


    my %resource = (subscriber_id => $prov_subs->id);

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );
    for my $cf_type (qw/cfu cfb cft cfna/) {
        my $mapping = $c->model('DB')->resultset('voip_cf_mappings')->search({
                subscriber_id => $prov_subs->id,
                type => $cf_type,
            })->first;
        if ($mapping) {
            $resource{$cf_type} = $self->_contents_from_cfm($c, $mapping, $item);
        } else {
            $resource{$cf_type} = {};
        }
    }
    if(keys %{$resource{cft}}){
        my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subs)->first;
        $ringtimeout_preference = $ringtimeout_preference ? $ringtimeout_preference->value : undef;
        $resource{cft}{ringtimeout} = $ringtimeout_preference;
    }

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

sub item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { 'me.status' => { '!=' => 'terminated' } },
            { prefetch => 'provisioning_voip_subscriber',},
        );
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id, $type) = @_;

    my $item_rs = $self->item_rs($c, $type);
    return $self->item_rs($c, $type)->search_rs({'me.id' => $id})->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $billing_subscriber_id = $item->id;
    my $prov_subs = $item->provisioning_voip_subscriber;
    die "need provisioning_voip_subscriber" unless $prov_subs;
    my $prov_subscriber_id = $prov_subs->id;

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        run => 1,
    );

    for my $type (qw/cfu cfb cft cfna/) {
        next unless "ARRAY" eq ref $resource->{$type}{destinations};
        for my $d (@{ $resource->{$type}{destinations} }) {
            if (exists $d->{timeout} && ! $d->{timeout}->is_integer) {
                $c->log->error("Invalid timeout in '$type'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid timeout in '$type'");
                return;
            }
        }
    }

    for my $type (qw/cfu cfb cft cfna/) {
        my $mapping = $c->model('DB')->resultset('voip_cf_mappings')->search_rs({
            subscriber_id => $prov_subscriber_id,
            type => $type,
        });
        my $mapping_count = $mapping->count;
        my $cf_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
                c => $c, prov_subscriber => $prov_subs, attribute => $type);
        my ($dset, $tset);
        if ($mapping_count == 0) {
            next unless (defined $resource->{$type});
            $mapping = $c->model('DB')->resultset('voip_cf_mappings')->create({
                subscriber_id => $prov_subscriber_id,
                type => $type,
            });
            $mapping->discard_changes; # get our row
        } elsif ($mapping_count > 1) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Not a simple cf. Multiple $type-s configured.");
            return;
        } else { # count is 1
            $mapping = $mapping->first;
            $dset = $mapping->destination_set;
            $tset = $mapping->time_set;
        }

        try {
            if($cf_preference->first) {
                $cf_preference->first->update({ value => $mapping->id });
            } else {
                $cf_preference->create({ value => $mapping->id });
            }

            my $primary_nr_rs = $item->primary_number;
            my $number;
            if ($primary_nr_rs) {
                $number = $primary_nr_rs->cc . ($primary_nr_rs->ac //'') . $primary_nr_rs->sn;
            } else {
                $number = ''
            }
            my $domain = $prov_subs->domain->domain // '';
            my $old_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($dset);
            if ($dset) {
                if ((defined $resource->{$type}{destinations}) && @{ $resource->{$type}{destinations}}) {
                    $dset->voip_cf_destinations->delete; #empty dset
                } else {
                    $dset->delete; # delete dset
                    $mapping_count = 0; # auto deleted by mysql
                }
            } else {
                if ((defined $resource->{$type}{destinations}) && @{ $resource->{$type}{destinations}}) {
                    $dset = $mapping->create_related('destination_set', {'name' => "quickset_$type", subscriber_id => $prov_subscriber_id,} );
                    $mapping->update({destination_set_id => $dset->id});
                }
            }
            if ($tset) {
                if ((defined $resource->{$type}{times}) && @{ $resource->{$type}{times}}) {
                    $tset->voip_cf_periods->delete; #empty tset
                } else {
                    $mapping_count && $mapping->update({time_set_id => undef});
                    if ($tset->name =~ m/^quickset_/) {
                        $tset->delete; # delete tset
                    }
                }
            } else {
                if ((defined $resource->{$type}{times}) && @{ $resource->{$type}{times}}) {
                    $tset = $mapping->create_related('time_set', {'name' => "quickset_$type", subscriber_id => $prov_subscriber_id,} );
                    $mapping->update({time_set_id => $tset->id});
                }
            }
            for my $d (@{ $resource->{$type}{destinations} }) {
                delete $d->{destination_set_id};
                delete $d->{simple_destination};
                $d->{destination} = NGCP::Panel::Utils::Subscriber::field_to_destination(
                        destination => $d->{destination},
                        number => $number,
                        domain => $domain,
                        uri => $d->{destination},
                    );
                $dset->voip_cf_destinations->update_or_create($d);
            }
            for my $t (@{ $resource->{$type}{times} }) {
                delete $t->{time_set_id};
                $tset->voip_cf_periods->update_or_create($t);
            }

            $dset->discard_changes if $dset; # update destinations
            my $new_autoattendant = NGCP::Panel::Utils::Subscriber::check_dset_autoattendant_status($dset);
            NGCP::Panel::Utils::Subscriber::check_cf_ivr(
                subscriber => $item,
                schema => $c->model('DB'),
                old_aa => $old_autoattendant,
                new_aa => $new_autoattendant,
            );

            unless ( $dset && $dset->voip_cf_destinations->count ) {
                $mapping->delete;
                $cf_preference->delete;
            }
        } catch($e) {
            $c->log->error("Error Updating '$type': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "CallForward '$type' could not be updated.");
            return;
        }
    }

    if ($resource->{cft}{ringtimeout} && $resource->{cft}{ringtimeout} > 0) {
        my $ringtimeout_preference = NGCP::Panel::Utils::Preferences::get_usr_preference_rs(
            c => $c, attribute => 'ringtimeout', prov_subscriber => $prov_subs);

        if($ringtimeout_preference->first) {
            $ringtimeout_preference->first->update({
                value => $resource->{cft}{ringtimeout},
            });
        } else {
            $ringtimeout_preference->create({
                value => $resource->{cft}{ringtimeout},
            });
        }
    }

    return $item;
}

sub _contents_from_cfm {
    my ($self, $c, $cfm_item, $sub) = @_;
    my (@times, @destinations);
    my $timeset_item = $cfm_item->time_set;
    my $dset_item = $cfm_item->destination_set;
    for my $time ($timeset_item ? $timeset_item->voip_cf_periods->all : () ) {
        push @times, {$time->get_inflated_columns};
        delete @{$times[-1]}{'time_set_id', 'id'};
    }
    for my $dest ($dset_item ? $dset_item->voip_cf_destinations->all : () ) {
        my ($d, $duri) = NGCP::Panel::Utils::Subscriber::destination_to_field($dest->destination);
        my $deflated;
        if($d eq "uri") {
            $deflated = NGCP::Panel::Utils::Subscriber::uri_deflate($duri,$sub) if $d eq "uri";
            $d = $dest->destination;
        }
        push @destinations, {$dest->get_inflated_columns,
                destination => $d,
                $deflated ? (simple_destination => $deflated) : (),
            };
        delete @{$destinations[-1]}{'destination_set_id', 'id'};
    }
    return {times => \@times, destinations => \@destinations};
}

1;
# vim: set tabstop=4 expandtab:
