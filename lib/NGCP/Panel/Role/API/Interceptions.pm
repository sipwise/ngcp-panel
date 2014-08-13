package NGCP::Panel::Role::API::Interceptions;
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
use NGCP::Panel::Form::InterceptionAPI;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('voip_intercept')->search({
        deleted => 0,
    });
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::InterceptionAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    $form //= $self->get_form($c);
    my $resource = $self->resource_from_item($c, $item, $form);

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
        ],
        relation => 'ngcp:'.$self->resource_name,
    );


    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resnames_to_dbnames {
    my ($self, $resource) = @_;

    my %fmap = (
        liid => "LIID",
        x2_host => "delivery_host",
        x2_port => "delivery_port",
        x2_user => "delivery_user",
        x2_password => "delivery_pass",
        x3_required => "cc_required",
        x3_host => "cc_delivery_host",
        x3_port => "cc_delivery_port",
    );
    foreach my $k(keys %fmap) {
        next unless exists($resource->{$k});
        $resource->{$fmap{$k}} = delete $resource->{$k};
    }

    return $resource;
}

sub dbnames_to_resnames {
    my ($self, $resource) = @_;

    my %fmap = (
        LIID => "liid",
        delivery_host => "x2_host",
        delivery_port => "x2_port",
        delivery_user => "x2_user",
        delivery_pass => "x2_password",
        cc_required => "x3_required",
        cc_delivery_host => "x3_host",
        cc_delivery_port => "x3_port",
    );
    foreach my $k(keys %fmap) {
        next unless exists($resource->{$k});
        $resource->{$fmap{$k}} = delete $resource->{$k};
    }

    return $resource;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    $resource = $self->dbnames_to_resnames($resource);

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $num_rs = $c->model('DB')->resultset('voip_numbers')->search(
        \[ 'concat(cc,ac,sn) = ?', $resource->{number}]
    );
    unless($num_rs->first) {
        $c->log->error("invalid number '$$resource{number}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number does not exist");
        last;
    }
    $resource->{reseller_id} = $num_rs->first->reseller_id;

    my $sub = $num_rs->first->subscriber;
    unless($sub) {
        $c->log->error("invalid number '$$resource{number}', not assigned to any subscriber");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number is not active");
        last;
    }
    $resource->{sip_username} = $sub->username;
    $resource->{sip_domain} = $sub->domain->domain;

    if($resource->{x3_required} && (!defined $resource->{x3_host} || !defined $resource->{x3_port})) {
        $c->log->error("Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing parameter 'x3_host' or 'x3_port' with 'x3_required' activated");
        last;
    }
    $resource->{x3_host} = $resource->{x3_port} = undef unless($resource->{x3_required});

    $resource->{modify_timestamp} = NGCP::Panel::Utils::DateTime::current_local;

    $resource = $self->resnames_to_dbnames($resource);
    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
