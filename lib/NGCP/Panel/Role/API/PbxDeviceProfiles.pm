package NGCP::Panel::Role::API::PbxDeviceProfiles;
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
use NGCP::Panel::Form::Device::Profile;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Device::Profile->new;
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
    return \%resource;
}

sub item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_profiles');
    if($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search(
            { 'device.reseller_id' => $c->user->reseller_id, },
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
        $c->log->error("Pbx device profile with name '$$resource{name}' already exists for config_id '$$resource{config_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device profile with this name already exists for this config");
        last;
    }
    my $config_rs = $c->model('DB')->resultset('autoprov_configs')->search({
        id => $resource->{config_id},
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
        $c->log->error("Pbx device config with confg_id '$$resource{config_id}' does not exist");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device config does not exist");
        last;
    }

    $item->update($resource);

    return $item;
}


1;
# vim: set tabstop=4 expandtab:
