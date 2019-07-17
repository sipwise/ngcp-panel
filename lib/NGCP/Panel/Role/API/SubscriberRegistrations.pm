package NGCP::Panel::Role::API::SubscriberRegistrations;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Kamailio;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('location');
    if($c->user->roles eq "admin") {
        $item_rs = $item_rs->search({

        },{
            join => { 'kam_subscriber' => 'provisioning_voip_subscriber'},
        });
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => { 'kam_subscriber' => 'provisioning_voip_subscriber' => { 'voip_subscriber' => { 'contract' => 'contact' }}},
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Subscriber::RegisteredAPI", $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);
    return unless $resource;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $resource->{subscriber_id})),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $user_agent = $resource->{user_agent};
    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
        exceptions => [ "subscriber_id" ],
    );
    $resource->{user_agent} = $user_agent;

    $resource->{id} = int($item->id);

    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };

    my $sub = $self->subscriber_from_item($c, $item);
    return unless($sub);
    $resource->{subscriber_id} = int($sub->id);
    $resource->{nat} = $resource->{cflags} & 64;

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub subscriber_from_item {
    my ($self, $c, $item) = @_;

    my $kam_subscriber = $item ? $item->kam_subscriber : undef;
    my $prov_subscriber = $kam_subscriber ? $kam_subscriber->provisioning_voip_subscriber : undef;
    my $sub = $prov_subscriber ? $prov_subscriber->voip_subscriber : undef;
    unless($sub && $prov_subscriber) {
        return;
    }
    return $sub;
}

sub subscriber_from_id {
    my ($self, $c, $id) = @_;

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.id' => $id,
        'me.status' => { '!=' => 'terminated' },
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $sub_rs = $sub_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    }
    my $sub = $sub_rs->first;
    unless($sub && $sub->provisioning_voip_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "No subscriber for subscriber_id found");
        return;
    }
    return $sub;
}

sub _item_by_aor {
    my ($self, $c, $sub, $contact) = @_;

    return $self->item_rs($c)->search({
        'me.contact'  => $contact,
        'me.username' => $sub->provisioning_voip_subscriber->username,
        '-or' => [
                'me.domain'   => $sub->provisioning_voip_subscriber->domain->domain,
                'me.domain'   => undef,
            ],
    })->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $create) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "subscriber_id" ],
        run => 1,
        #form_params => { 'use_fields_for_input_without_param' => 1 },
    );

    my $sub = $self->subscriber_from_id($c, $resource->{subscriber_id});
    return unless $sub;

    unless($create) {
        $self->delete_item($c, $item);
    }
    my $cflags = 0;
    $cflags |= 64 if($form->values->{nat});

    NGCP::Panel::Utils::Kamailio::create_location($c,
        $sub->provisioning_voip_subscriber,
        $form->values->{contact},
        $form->values->{q},
        $form->values->{expires},
        0, # flags
        $cflags
    );

    NGCP::Panel::Utils::Kamailio::flush($c);

    return $create ? 1 : $item; # on create, we dont have the item yet
}

sub fetch_item {
    my ($self, $c, $resource, $form, $old_item) = @_;

    return unless $form;

    my $sub = $self->subscriber_from_id($c, $resource->{subscriber_id});
    return unless $sub;

    my $item;
    my $flush_timeout = 30;

    while ($flush_timeout) {
        $item = $self->_item_by_aor($c, $sub, $form->values->{contact});
        if ($item && (!$old_item || $item->id != $old_item->id)) {
            last;
        }
        $item = undef;
        $flush_timeout--;
        last unless $flush_timeout;
        sleep 1;
    }

    unless ($item) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Could not find a new registration entry in the db, that might be caused by the kamailio flush mechanism, where the item has been updated successfully");
        return;
    }

    return $item;
}

sub delete_item {
    my ($self, $c, $item) = @_;

    my $sub = $self->subscriber_from_item($c, $item);
    return unless($sub);
    NGCP::Panel::Utils::Kamailio::delete_location_contact($c,
        $sub, $item->contact);
    NGCP::Panel::Utils::Kamailio::flush($c);
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
