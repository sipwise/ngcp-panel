package NGCP::Panel::Role::API::PbxDeviceProfiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Device::Profile", $c);
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    my $type = 'pbxdeviceprofiles';

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
            Data::HAL::Link->new(relation => 'ngcp:pbxdeviceconfigs', href => sprintf("/api/pbxdeviceconfigs/%d", $item->config_id)),
            Data::HAL::Link->new(relation => 'ngcp:pbxdevicemodels', href => sprintf("/api/pbxdevicemodels/%d", $item->config->device_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    my $resource = $self->resource_from_item($c, $item);

    $self->expand_fields($c, $resource);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;

    my %resource = $item->get_inflated_columns;
    delete $resource{config_id};

    my $form = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{id} = int($item->id);
    $resource{config_id} = int($item->config_id);
    $resource{device_id} = int($item->config->device_id) if ($item->config);
    return \%resource;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_profiles');
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search(
            { 'device.reseller_id' => $c->user->reseller_id, },
            { prefetch => { 'config' => 'device', }});
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $item_rs->search(
            { 'device.reseller_id' => $c->user->contract->contact->reseller_id, },
            { prefetch => { 'config' => 'device', }});
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

    my $dup_item = $c->model('DB')->resultset('autoprov_profiles')->find({
        config_id => $resource->{config_id},
        name => $resource->{name},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device profile with this name already exists for this config",
                     "Pbx device profile with name '$$resource{name}' already exists for config_id '$$resource{config_id}'");
        last;
    }
    my $config_rs = $c->model('DB')->resultset('autoprov_configs')->search({
        'me.id' => $resource->{config_id},
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $config_rs = $config_rs->search({
            'device.reseller_id' => $c->user->reseller_id,
        },{
            join => 'device',
        });
    }
    my $config = $config_rs->first;
    unless($config) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device config does not exist",
                     "Pbx device config with confg_id '$$resource{config_id}' does not exist");
        last;
    }

    delete $resource->{device_id};

    $item->update($resource);

    return $item;
}


1;
# vim: set tabstop=4 expandtab:
