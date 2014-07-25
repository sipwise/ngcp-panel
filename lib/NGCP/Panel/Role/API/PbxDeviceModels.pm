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
use NGCP::Panel::Form::Device::ModelAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Device::ModelAPI->new($c);
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

    $resource{reseller_id} = int($item->reseller_id);
    $resource{id} = int($item->id);
    $resource{linerange} = [];
    foreach my $range($item->autoprov_device_line_ranges->all) {
        my $r = { $range->get_inflated_columns };
        foreach my $f(qw/device_id/) {
            delete $r->{$f};
        }
        $r->{id} = int($r->{id});
        $r->{num_lines} = int($r->{num_lines});
        foreach my $f(qw/can_private can_shared can_blf/) {
            $r->{$f} = $r->{$f} ? JSON::true : JSON::false;
        }

        push @{ $resource{linerange} }, $r;
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
        $c->log->error("invalid reseller_id '$$resource{reseller_id}', does not exist");
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

    $item->update($resource);

    my @existing_range = ();
    my $range_rs = $item->autoprov_device_line_ranges;
    foreach my $range(@{ $linerange }) {
        next unless(defined $range);
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

1;
# vim: set tabstop=4 expandtab:
