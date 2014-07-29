package NGCP::Panel::Role::API::CCMapEntries;
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
use NGCP::Panel::Form::CCMapEntriesAPI;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::CCMapEntriesAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form = $self->get_form($c);

    my $prov_subs = $item->provisioning_voip_subscriber;

    die "no provisioning_voip_subscriber" unless $prov_subs;

    my %resource = (subscriber_id => $item->id);

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

    $resource{mappings} = [];
    for my $mapping ($item->provisioning_voip_subscriber->voip_cc_mappings->all) {
        push $resource{mappings}, {
                auth_key => $mapping->auth_key,
            };
    }

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
        exceptions => ['subscriber_id'],
    );

    $hal->resource(\%resource);
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search(
            { status => { '!=' => 'terminated' } },
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
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->search_rs({'me.id' => $id})->first;
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

    my $uuid = $item->uuid;

    try {
        $prov_subs->voip_cc_mappings->delete;
        for my $mapping (@{ $resource->{mappings} }) {
            $prov_subs->voip_cc_mappings->create({
                source_uuid => $uuid,
                auth_key => $mapping->{auth_key},
            });
        }
    } catch($e) {
        $c->log->error("Error Updating ccmapentry for $uuid: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "CCMapEntry could not be updated.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
