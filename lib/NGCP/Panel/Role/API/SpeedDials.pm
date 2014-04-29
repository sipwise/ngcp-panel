package NGCP::Panel::Role::API::SpeedDials;
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
use Test::More;
use NGCP::Panel::Form::Subscriber::SpeedDialAPI;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::Subscriber::SpeedDialAPI->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item) = @_;

    my $p_subs = $item->provisioning_voip_subscriber;
    my $resource = { subscriber_id => $item->id, speeddials => $self->speeddials_from_subscriber($p_subs) };

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:speeddials', href => sprintf("/api/speeddials/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $form = $self->get_form($c);
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
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({ status => { '!=' => 'terminated' } });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
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
    # $old_resource is unused

    my $billing_subs = $item;
    my $prov_subs = $billing_subs->provisioning_voip_subscriber;
    my $speeddials_rs = $prov_subs->voip_speed_dials;

    if (ref $resource->{speeddials} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'speeddials'. Must be an array.");
        return;
    }

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    try {
        my $domain = $prov_subs->domain->domain // '';
        $speeddials_rs->delete;
        for my $spd (@{ $resource->{speeddials} }) {
            $speeddials_rs->create({
                destination => $self->get_sip_uri($spd->{destination}, $domain),
                slot => $spd->{slot},
            });
        }
    } catch($e) {
        $c->log->error("failed to update speeddials: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update speeddials.");
        return;
    };

    return $billing_subs;
}

sub speeddials_from_subscriber {
    my ($self, $prov_subscriber) = @_;

    my @speeddials;
    for my $s ($prov_subscriber->voip_speed_dials->all) {
        push @speeddials, {slot => $s->slot, destination => $s->destination};
    }
    return \@speeddials;
}

sub get_sip_uri {
    my ($self, $d, $domain) = @_;

    if($d !~ /\@/) {
        $d .= '@'.$domain;
    }
    if($d !~ /^sip:/) {
        $d = 'sip:' . $d;
    }
    return $d;
}

1;
# vim: set tabstop=4 expandtab:
