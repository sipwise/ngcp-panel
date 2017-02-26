package NGCP::Panel::Role::API::CCMapEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::CFSimpleAPI;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Form::CCMapEntries;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::CCMapEntries->new;
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form = $self->get_form($c);

    my $prov_subs = $item->provisioning_voip_subscriber;

    die "no provisioning_voip_subscriber" unless $prov_subs;

    my %resource = (subscriber_id => $item->id);

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%s", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:$type", href => sprintf("/api/%s/%s", $type, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
            $self->get_journal_relation_link($item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $resource{mappings} = [];
    for my $mapping ($item->provisioning_voip_subscriber->voip_cc_mappings->all) {
        push @{ $resource{mappings} }, {
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

sub _item_rs {
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
