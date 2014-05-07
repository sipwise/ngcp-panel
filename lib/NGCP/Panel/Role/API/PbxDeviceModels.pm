package NGCP::Panel::Role::API::PbxDeviceModels;
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
use NGCP::Panel::Form::Device::Model;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Device::Model->new;
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    my $type = 'pbxdevicemodels';

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
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->resource_from_item($c, $item);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;

    my %resource = $item->get_inflated_columns;
    delete $resource{front_image};
    delete $resource{mac_image};

    my $form = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{reseller_id} = int($item->reseller_id);
    $resource{id} = int($item->id);
    return \%resource;
}

sub item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_devices');
    if($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
