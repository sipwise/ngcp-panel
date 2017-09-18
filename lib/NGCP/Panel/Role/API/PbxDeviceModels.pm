package NGCP::Panel::Role::API::PbxDeviceModels;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

use NGCP::Panel::Form::Device::ModelAPI;
use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Device;

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
    return [qw/admin reseller subscriberadmin/];
}

sub hal_links{
    my($self, $c, $item, $resource, $form) = @_;
    return [
        NGCP::Panel::Utils::DataHalLink->new(relation => "ngcp:pbxdevicefirmwares", href => sprintf("/api/pbxdevicefirmwares/?device_id=%d", $item->id)),
    ];
}

sub get_form {
    my ($self, $c) = @_;
    #use_fields_for_input_without_param
    return NGCP::Panel::Form::Device::ModelAPI->new(ctx => $c);
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_devices')
        ->search_rs(undef,{ prefetch => {autoprov_device_line_ranges => 'annotations'} });
    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    } elsif ($c->user->roles eq "subscriberadmin") {
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

sub process_form_resource{
    my($self,$c, $item, $old_resource, $resource, $form, $process_extras) = @_;

    $resource->{type} //= 'phone';

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $reseller_id = $c->user->reseller_id;
    }
    $resource->{reseller_id} = $reseller_id;

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
            #last? not next?
            return;
        }
        foreach my $label(@{ $keys }) {
            unless(ref $label eq "HASH") {
                $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
                return;
            }
        }
    }
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

sub update_item {

    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    $form //= $self->get_form($c);

    NGCP::Panel::Utils::Device::store_and_process_device_model_before_ranges($c, $item, $resource);

    my $linerange = delete $resource->{linerange};
    my @existing_range = ();
    my $range_rs = $item->autoprov_device_line_ranges;
    foreach my $range(@{ $linerange }) {
        if(defined $range->{id}) {
            my $range_by_id = $c->model('DB')->resultset('autoprov_device_line_ranges')->find($range->{id});
            if( $range_by_id && ( $range_by_id->device_id != $item->id ) ){
            #this is extension linerange, stop processing this linerange completely
            #we should care about it here due to backward compatibility, so API user still can make GET => PUT without excluding extension ranges
                next;
            }
        }

        $range->{num_lines} = @{ $range->{keys} }; # backward compatibility
        my $keys = delete $range->{keys};
        my $range_db;
        if(defined $range->{id}) {
            # should be an existing range, do update
            $range_db = $range_rs->find($range->{id});
            delete $range->{id};
            unless($range_db) {#really this is strange situation
                delete $range->{id};
                $range_db = $range_rs->create($range);
            } else {
                # formhandler only passes set check-boxes, so explicitely unset here
                $range->{can_private} //= 0;
                $range->{can_shared} //= 0;
                $range->{can_blf} //= 0;
                $range_db->update($range);
            }
        } else {
            # new range
            $range_db = $range_rs->create($range);
        }

        $range_db->annotations->delete;
        my $i = 0;
        foreach my $label(@{ $keys }) {
            $label->{line_index} = $i++;
            $label->{position} = delete $label->{labelpos};
            $range_db->annotations->create($label);
        }

        push @existing_range, $range_db->id; # mark as valid (delete others later)

        # delete field device line assignments with are out-of-range or use a
        # feature which is not supported anymore after edit
        foreach my $fielddev_line($c->model('DB')->resultset('autoprov_field_device_lines')
            ->search({ linerange_id => $range_db->id })->all) {
            if($fielddev_line->key_num >= $range_db->num_lines ||
               ($fielddev_line->line_type eq 'private' && !$range_db->can_private) ||
               ($fielddev_line->line_type eq 'shared' && !$range_db->can_shared) ||
               ($fielddev_line->line_type eq 'blf' && !$range_db->can_blf)) {

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
