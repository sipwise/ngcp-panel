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
use JSON qw();
use File::Type;
use Data::Dumper;
use NGCP::Panel::Form::Device::ModelAPI;
use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Device;

sub get_form {
    my ($self, $c) = @_;
    my $form = NGCP::Panel::Form::Device::ModelAPI->new(ctx => $c);
    return $form;
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    #my $type = 'pbxdevicemodels';

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
            Data::HAL::Link->new(relation => "ngcp:pbxdevicefirmwares", href => sprintf("/api/pbxdevicefirmwares/?device_id=%d", $item->id)),
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

    foreach my $field (qw/reseller_id id extensions_num/){
        $resource{$field} = int($item->$field // 0);
    }
    foreach my $field (qw/linerange connectable_models/){
        $resource{$field} = [];
    }
    foreach my $range($item->autoprov_device_line_ranges->all) {
        $self->process_range( \%resource, $range );
    }
    if('extension' eq $item->type){
        # show possible devices for extension
        use Data::Dumper;
        $c->log->debug(Dumper($item->autoprov_extension_device_link->all));
        $resource{connectable_models} = [map {$_->device->id} ($item->autoprov_extension_device_link->all) ];
    }else{
        # we don't need show possible extensions - we will show their ranges
        # add ranges of the possible extensions
        foreach my $extension_link ($item->autoprov_extensions_link->all){
            my $extension = $extension_link->extension;
            foreach my $range($extension->autoprov_device_line_ranges->all) {
                $self->process_range( \%resource, $range, sub { my $r = shift; $r->{extension_range} = $extension->id;} );# 
            }
        }
    }
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

sub update_item {

    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    $form //= $self->get_form($c);

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $resource->{reseller_id} = $c->user->reseller_id;
    }

    my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
    unless($reseller) {
        $c->log->error("invalid reseller_id '".((defined $resource->{reseller_id})?$resource->{reseller_id} : "undefined")."', does not exist");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller_id, does not exist");
        return;
    }

    my $dup_item;
    $dup_item = $c->model('DB')->resultset('autoprov_devices')->find({
        reseller_id => $resource->{reseller_id},
        vendor => $resource->{vendor},
        model => $resource->{model},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("device model with vendor '$$resource{vendor}' and model '$$resource{model}'already exists for reseller_id '$$resource{reseller_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Device model already exists for this reseller");
        return;
    }

    my $linerange = delete $resource->{linerange};
    unless(ref $linerange eq "ARRAY") {
        $c->log->error("linerange must be array");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange parameter, must be array");
        return;
    }


    my $ft = File::Type->new();
    if($resource->{front_image}) {
        my $front_image = delete $resource->{front_image};
        $resource->{front_image} = $front_image->slurp;
        $resource->{front_image_type} = $ft->mime_type($resource->{front_image});
    }
    if($resource->{mac_image}) {
        my $front_image = delete $resource->{mac_image};
        $resource->{mac_image} = $front_image->slurp;
        $resource->{mac_image_type} = $ft->mime_type($resource->{mac_image});
    }
    my $connectable_models = delete $resource->{connectable_models};
    my $sync_parameters = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_prefetch($c, $item, $resource);
    my $credentials = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_prefetch($c, $item, $resource);
    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_clear($c, $resource);
    $item->update($resource);
    $c->model('DB')->resultset('autoprov_sync')->search_rs({
        device_id => $item->id,
    })->delete;
    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_store($c, $item, $credentials);
    NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_store($c, $item, $sync_parameters);
    NGCP::Panel::Utils::DeviceBootstrap::dispatch_devmod($c, 'register_model', $item);
    NGCP::Panel::Utils::Device::process_connectable_models($c, 1, $item, $connectable_models );
    my @existing_range = ();
    my $range_rs = $item->autoprov_device_line_ranges;
    foreach my $range(@{ $linerange }) {

        unless(ref $range eq "HASH") {
            $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
            return;
        }
        foreach my $elem(qw/can_private can_shared can_blf keys/) {
            unless(exists $range->{$elem}) {
                $c->log->error("missing mandatory attribute '$elem' in a linerange element");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, missing attribute '$elem'");
                return;
            }
        }
        unless(ref $range->{keys} eq "ARRAY") {
            $c->log->error("linerange.keys must be array");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange.keys parameter, must be array");
            last;
        }
        $range->{num_lines} = @{ $range->{keys} }; # backward compatibility
        my $keys = delete $range->{keys};
        my $old_range;
        if(defined $range->{id}) {
            # should be an existing range, do update
            $old_range = $range_rs->find($range->{id});
            delete $range->{id};
            unless($old_range) {
                $old_range = $range_rs->create($range);
            } else {
                # formhandler only passes set check-boxes, so explicitely unset here
                $range->{can_private} //= 0;
                $range->{can_shared} //= 0;
                $range->{can_blf} //= 0;
                $old_range->update($range);
            }
        } else {
            # new range
            $old_range = $range_rs->create($range);
        }

        $old_range->annotations->delete;
        my $i = 0;
        foreach my $label(@{ $keys }) {
            unless(ref $label eq "HASH") {
                $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
                return;
            }

            $label->{line_index} = $i++;
            $label->{position} = delete $label->{labelpos};
            $old_range->annotations->create($label);
        }

        push @existing_range, $old_range->id; # mark as valid (delete others later)

        # delete field device line assignments with are out-of-range or use a
        # feature which is not supported anymore after edit
        foreach my $fielddev_line($c->model('DB')->resultset('autoprov_field_device_lines')
            ->search({ linerange_id => $old_range->id })->all) {
            if($fielddev_line->key_num >= $old_range->num_lines ||
               ($fielddev_line->line_type eq 'private' && !$old_range->can_private) ||
               ($fielddev_line->line_type eq 'shared' && !$old_range->can_shared) ||
               ($fielddev_line->line_type eq 'blf' && !$old_range->can_blf)) {

               $fielddev_line->delete;
           }
        }
    }
    # delete invalid range ids (e.g. removed ones)
    $range_rs->search({
        id => { 'not in' => \@existing_range },
    })->delete_all;
    
    return $item;
}
sub process_range {
    my($self, $resource, $range, $process_range_cb ) = @_;
    my $r = { $range->get_inflated_columns };
    foreach my $f(qw/device_id num_lines/) {
        delete $r->{$f};
    }
    $r->{id} = int($r->{id});
    foreach my $f(qw/can_private can_shared can_blf/) {
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
