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
use NGCP::Panel::Form::Subscriber::SubscriberAPI;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;
use NGCP::Panel::Utils::Subscriber;

sub get_form {
    my ($self, $c) = @_;

    return '';# NGCP::Panel::Form::Subscriber::SubscriberAPI->new;
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
    my ($self, $c, $item, $full_resource, $resource, $form) = @_;

    my $subscriber = $item;
    my $customer = $full_resource->{customer};
    my $admin = $full_resource->{admin};
    my $alias_numbers = $full_resource->{alias_numbers};
    my $preferences = $full_resource->{preferences};

    if($subscriber->status ne $resource->{status}) {
        if($resource->{status} eq 'locked') {
            $resource->{lock} = 4;
        } elsif($subscriber->status eq 'locked' && $resource->{status} eq 'active') {
            $resource->{lock} ||= 0;
        } elsif($resource->{status} eq 'terminated') {
            try {
                NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);
            } catch($e) {
                $c->log->error("failed to terminate subscriber id ".$subscriber->id);
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to terminate subscriber");
            }
            return;
        }
    }
    if(defined $resource->{lock}) {
        try {
            NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                c => $c,
                prov_subscriber => $subscriber->provisioning_voip_subscriber,
                level => $resource->{lock},
            );
        } catch($e) {
            $c->log->error("failed to lock subscriber id ".$subscriber->id." with level ".$resource->{lock});
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update subscriber lock");
            return;
        };
    }

    NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
        schema => $c->model('DB'),
        primary_number => $resource->{e164},
        alias_numbers => $alias_numbers,
        reseller_id => $customer->contact->reseller_id,
        subscriber_id => $subscriber->id,
    );

    my $billing_res = {
        external_id => $resource->{external_id},
        status => $resource->{status},
    };
    my $provisioning_res = {
        password => $resource->{password},
        webusername => $resource->{webusername},
        webpassword => $resource->{webpassword},
        admin => $resource->{administrative},
        is_pbx_group => $resource->{is_pbx_group},
        pbx_group_id => $resource->{pbx_group_id},
        modify_timestamp => NGCP::Panel::Utils::DateTime::current_local,

    };

    $subscriber->update($billing_res);
    $subscriber->provisioning_voip_subscriber->update($provisioning_res);
    $subscriber->discard_changes;
    NGCP::Panel::Utils::Subscriber::update_preferences(
        c => $c,
        prov_subscriber => $subscriber->provisioning_voip_subscriber,
        preferences => $preferences,
    );

    # TODO: status handling (termination, ...)

    return $subscriber;
}

sub speeddials_from_subscriber {
    my ($self, $prov_subscriber) = @_;

    my @speeddials;
    for my $s ($prov_subscriber->voip_speed_dials->all) {
        push @speeddials, {slot => $s->slot, destination => $s->destination};
    }
    return \@speeddials;
}

1;
# vim: set tabstop=4 expandtab:
