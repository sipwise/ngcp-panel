package NGCP::Panel::Role::API::AutoAttendants;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use Test::More;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::AutoAttendantAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item) = @_;

    my $p_subs = $item->provisioning_voip_subscriber;
    my $resource = { subscriber_id => $item->id, slots => $self->_autoattendants_from_subscriber($p_subs) };

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
            Data::HAL::Link->new(relation => 'ngcp:autoattendants', href => sprintf("/api/autoattendants/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->id)),
            $self->get_journal_relation_link($c, $item->id),
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

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({ 'me.status' => { '!=' => 'terminated' } },
            {join => 'provisioning_voip_subscriber'});
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search({
            'provisioning_voip_subscriber.account_id' => $c->user->account_id,
        });
    } else {
        return;  # subscriber role not allowed
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
    my $aa_rs = $prov_subs->voip_pbx_autoattendants;

    if (ref $resource->{slots} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'slots'. Must be an array.");
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
        $aa_rs->delete;
        for my $aa (@{ $resource->{slots} }) {
            $aa_rs->create({
                destination => $self->get_sip_uri($aa->{destination}, $domain),
                choice => $aa->{slot},
                uuid => $prov_subs->uuid,
            });
        }
    } catch($e) {
        $c->log->error("failed to update autoattendants: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update autoattendants.");
        return;
    };

    return $billing_subs;
}

sub _autoattendants_from_subscriber {
    my ($self, $prov_subscriber) = @_;

    my @aas;
    for my $s ($prov_subscriber->voip_pbx_autoattendants->all) {
        push @aas, {destination => $s->destination, slot => $s->choice};
    }
    return \@aas;
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
