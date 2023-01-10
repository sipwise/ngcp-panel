package NGCP::Panel::Role::API::PbxDeviceModels;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Device;
use NGCP::Panel::Utils::DeviceBootstrap;
use Data::Dumper;
use boolean qw(true);
use JSON qw();
use File::Type;

sub item_name{
    return 'pbxdevicemodels';
}

sub resource_name{
    return 'pbxdevicemodels';
}

sub dispatch_path{
    return '/api/pbxdevicemodels/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodels';
}

sub config_allowed_roles {
    return {
        'Default' => [qw/admin reseller subscriberadmin subscriber/],
        #GET will use default
        'POST'    => [qw/admin reseller/],
        'PUT'     => [qw/admin reseller/],
        'PATCH'   => [qw/admin reseller/],
    };
}

sub hal_links{
    my($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => "ngcp:pbxdevicefirmwares", href => sprintf("/api/pbxdevicefirmwares/?device_id=%d", $item->id)),
    ];
}

sub get_form {
    my ($self, $c) = @_;
    #use_fields_for_input_without_param
    return (NGCP::Panel::Form::get("NGCP::Panel::Form::Device::ModelAPI", $c));
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_devices')
        ->search_rs(undef,{ prefetch => {autoprov_device_line_ranges => 'annotations'} });
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif ($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        my $reseller_id = $c->user->contract->contact->reseller_id;
        return unless $reseller_id;
        $item_rs = $item_rs->search({
            reseller_id => $reseller_id,
        });
    }
    return $item_rs;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;

    my %resource = $item->get_inflated_columns;
    delete $resource{front_image};
    delete $resource{mac_image};
    delete $resource{front_thumbnail};

    my ($form) = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    foreach my $field (qw/reseller_id id extensions_num/){
        $resource{$field} = int($item->$field // 0);
    }
    foreach my $field (qw/linerange connectable_models/){
        $resource{$field} = [];
    }
    foreach my $range($item->autoprov_device_line_ranges->all) {
        $self->process_range( \%resource, $range );
    }

    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_prefetch_api($c, $item,\%resource);

    if('extension' eq $item->type){
        # show possible devices for extension
        $resource{connectable_models} = [map {$_->device->id} ($item->autoprov_extension_device_link->all) ];
    }else{
        # we don't need show possible extensions - we will show their ranges
        # add ranges of the possible extensions
        foreach my $extension_link ($item->autoprov_extensions_link->all){
            my $extension = $extension_link->extension;
            push @{$resource{connectable_models}}, $extension->id;
            foreach my $range($extension->autoprov_device_line_ranges->all) {
                $self->process_range( \%resource, $range, sub {
                    my $r = shift;
                    $r->{extension_range} = $extension->id;
                } );#
            }
        }
    }
    return \%resource;
}

sub pre_process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    #API form doesn't consider default value somehow
    $resource->{type} //= 'phone';
}

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    $resource->{type} //= 'phone';

    my $reseller_id = delete $resource->{reseller_id};
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }
    $resource->{reseller_id} = $reseller_id;

    my $ft = File::Type->new();
    if($resource->{front_image}) {
        my $image = delete $resource->{front_image};
        $resource->{front_image} = $image->slurp;
        $resource->{front_image_type} = $ft->mime_type($resource->{front_image});
    }
    if($resource->{front_thumbnail}) {
        my $image = delete $resource->{front_thumbnail};
        $resource->{front_thumbnail} = $image->slurp;
        $resource->{front_thumbnail_type} = $ft->mime_type($resource->{front_thumbnail});
    }
    if($resource->{mac_image}) {
        my $image = delete $resource->{mac_image};
        $resource->{mac_image} = $image->slurp;
        $resource->{mac_image_type} = $ft->mime_type($resource->{mac_image});
    }

    return $resource;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $schema = $c->model('DB');

    my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
    unless($reseller) {
        $c->log->error("invalid reseller_id '".((defined $resource->{reseller_id})?$resource->{reseller_id} : "undefined")."', does not exist");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller_id, does not exist");
        return;
    }

    my $linerange = $resource->{linerange};
    unless(ref $linerange eq "ARRAY") {
        $c->log->error("linerange must be array");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange parameter, must be array");
        return;
    }
    foreach my $range(@{ $linerange }) {

        unless(ref $range eq "HASH") {
            $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
            return;
        }
        foreach my $elem(qw/can_private can_shared can_blf can_speeddial can_forward can_transfer keys/) {
            unless(exists $range->{$elem}) {
                $c->log->error("missing mandatory attribute '$elem' in a linerange element");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, missing attribute '$elem'");
                return;
            }
        }
        unless(ref $range->{keys} eq "ARRAY") {
            $c->log->error("linerange.keys must be array");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange.keys parameter, must be array");
            #last? not next?
            return;
        }
        foreach my $label(@{ $range->{keys} }) {
            unless(ref $label eq "HASH") {
                $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
                return;
            }
        }
    }
    return 1;
}

sub check_duplicate{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $existing_item = $c->model('DB')->resultset('autoprov_devices')->find({
        reseller_id => $resource->{reseller_id},
        vendor => $resource->{vendor},
        model => $resource->{model},
    });
    if($existing_item && (!$item || $item->id != $existing_item->id)) {
        $c->log->error("device model with vendor '$$resource{vendor}' and model '$$resource{model}'already exists for reseller_id '$$resource{reseller_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Device model already exists for this reseller");
        return;
    }
    return 1;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    NGCP::Panel::Utils::Device::store_and_process_device_model($c, $item, $resource);

    return $item;
}

sub process_range {
    my($self, $resource, $range, $process_range_cb ) = @_;
    my $r = { $range->get_inflated_columns };
    foreach my $f(qw/device_id num_lines/) {
        delete $r->{$f};
    }
    $r->{id} = int($r->{id});
    foreach my $f(qw/can_private can_shared can_blf can_speeddial can_forward can_transfer/) {
        $r->{$f} = $r->{$f} ? JSON::true : JSON::false;
    }
    $r->{keys} = [];
    foreach my $key($range->annotations->all) {
        push @{ $r->{keys} }, {
            x => int($key->x),
            y => int($key->y),
            labelpos => $key->position,
        };
    }
    $r->{num_lines} = @{ $r->{keys} };
    ( ( defined $process_range_cb ) && ( 'CODE' eq ref $process_range_cb ) ) and $process_range_cb->($r);
    push @{ $resource->{linerange} }, $r;
}

1;
# vim: set tabstop=4 expandtab:
