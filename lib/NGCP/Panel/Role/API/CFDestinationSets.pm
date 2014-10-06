package NGCP::Panel::Role::API::CFDestinationSets;
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
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Form::CFDestinationSetAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CFDestinationSetAPI->new;
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
            $deflated = NGCP::Panel::Utils::Subscriber::uri_deflate($duri, $item->subscriber->voip_subscriber);
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
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => [ "subscriber_id" ],
    );
    $hal->resource(\%resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_destination_sets');
    } elsif ($c->user->roles eq "reseller") {
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
        exceptions => [ "subscriber_id" ],
    );

    if (! exists $resource->{destinations} ) {
        $resource->{destinations} = [];
    }
    if (ref $resource->{destinations} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'destinations'. Must be an array.");
        return;
    }
    for my $d (@{ $resource->{destinations} }) {
        if (exists $d->{timeout} && ! $d->{timeout}->is_integer) {
            $c->log->error("Invalid field 'timeout'.");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'timeout'.");
            return;
        }
    }

    my $b_subscriber = $schema->resultset('voip_subscribers')->find($resource->{subscriber_id});
    unless ($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        last;
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
                schema => $schema,
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

1;
# vim: set tabstop=4 expandtab:
