package NGCP::Panel::Role::API::PbxDeviceConfigs;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub resource_name{
    return 'pbxdeviceconfigs';
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('autoprov_configs');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'device.reseller_id' => $c->user->reseller_id
        },{
            join => 'device',
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Device::ConfigAPI", $c);
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;

    my $resource = { $item->get_inflated_columns };
    delete $resource->{data};

    return $resource;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    my $binary = delete $resource->{data};
    $resource->{content_type} = $c->request->header('Content-Type');

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $model_rs = $c->model('DB')->resultset('autoprov_devices')->search({ 
        id => $resource->{device_id} 
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $model_rs = $model_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    my $model = $model_rs->first;
    unless($model) {
        $c->log->error("invalid device_id '$$resource{device_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device model does not exist");
        last;
    }

    $resource->{data} = $binary;

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
