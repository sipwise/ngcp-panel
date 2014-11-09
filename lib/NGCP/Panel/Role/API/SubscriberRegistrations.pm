package NGCP::Panel::Role::API::SubscriberRegistrations;
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
use NGCP::Panel::Form::Subscriber::RegisteredAPI;
use NGCP::Panel::Utils::Kamailio;

sub item_rs {
    my ($self, $c) = @_;

    my @joins = ();;
    if($c->config->{features}->{multidomain}) {
        push @joins, 'domain';
    }
    my $item_rs = $c->model('DB')->resultset('location');
    if($c->user->roles eq "admin") {
        $item_rs = $item_rs->search({
            
        },{
            join => [@joins,'subscriber'],
        });
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'contact.reseller_id' => $c->user->reseller_id 
        },{
            join => [@joins, { 'subscriber' => { 'voip_subscriber' => { 'contract' => 'contact' }}} ],
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Subscriber::RegisteredAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);
    return unless $resource;

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
            Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $resource->{subscriber_id})),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
        exceptions => [ "subscriber_id" ],
    );

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

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        username => $item->username,
        status => { '!=' => 'terminated' },
    });
    if($c->config->{features}->{multidomain}) {
        $sub_rs = $sub_rs->search({
            'domain.domain' => $item->domain->domain,
        }, {
            join => 'domain',
        });
    }
    my $sub = $sub_rs->first;
    unless($sub && $sub->provisioning_voip_subscriber) {
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

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $create) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [ "subscriber_id" ],
    );

    my $sub = $self->subscriber_from_id($c, $resource->{subscriber_id});
    return unless($sub);

    unless($create) {
        $self->delete_item($c, $item);
    }
    my $cflags = 0;
    $cflags |= 64 if($resource->{nat});
    NGCP::Panel::Utils::Kamailio::create_location($c,
        $sub->provisioning_voip_subscriber,
        $resource->{contact},
        $resource->{q},
        $resource->{expires},
        0, # flags
        $cflags
    );

    unless($create) {
        # we need to reload it since we changed the content via an external
        # xmlrpc call
        $item->discard_changes;

        return $item;
    }
}

sub delete_item {
    my ($self, $c, $item) = @_;

    my $sub = $self->subscriber_from_item($c, $item);
    return unless($sub);
    NGCP::Panel::Utils::Kamailio::delete_location_contact($c,
        $sub, $item->contact);
    return 1;
}

1;
# vim: set tabstop=4 expandtab:
