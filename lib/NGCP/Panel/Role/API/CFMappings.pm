package NGCP::Panel::Role::API::CFMappings;
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
use NGCP::Panel::Form::CFMappingsAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CFMappingsAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my $resource = { subscriber_id => $item->id, cfu => [], cfb => [], cfna => [], cft => [], };
    my $b_subs_id = $item->id;
    my $p_subs_id = $item->provisioning_voip_subscriber->id;

    for my $mapping ($item->provisioning_voip_subscriber->voip_cf_mappings->all) {
        my $dset = $mapping->destination_set ? $mapping->destination_set->name : undef;
        my $tset = $mapping->time_set ? $mapping->time_set->name : undef;
        push $resource->{$mapping->type}, {
                destinationset => $dset,
                timeset => $tset,
            };
    }

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
        resource => $resource,
        run => 0,
    );
    $hal->resource($resource);
    return $hal;
}

sub item_rs {
    my ($self, $c, $type) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { status => { '!=' => 'terminated' } },
            { prefetch => 'provisioning_voip_subscriber',}
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

    my $subscriber = $schema->resultset('provisioning_voip_subscribers')->find($resource->{subscriber_id});
    unless ($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }

    try {
        my $primary_nr_rs = $subscriber->voip_subscriber->primary_number;
        my $number;
        if ($primary_nr_rs) {
            $number = $primary_nr_rs->cc . ($primary_nr_rs->ac //'') . $primary_nr_rs->sn;
        } else {
            $number = ''
        }
        my $domain = $subscriber->domain->domain // '';

        $item->update({
                name => $resource->{name},
                subscriber_id => $resource->{subscriber_id},
            })->discard_changes;
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
    } catch($e) {
        $c->log->error("failed to create cfdestinationset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfdestinationset.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
