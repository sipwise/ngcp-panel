package NGCP::Panel::Role::API::PbxDevices;
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
use NGCP::Panel::Form::Customer::PbxFieldDeviceAPI;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Customer::PbxFieldDeviceAPI->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item) = @_;
    my $form;
    my $type = 'pbxdevices';

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
            Data::HAL::Link->new(relation => 'ngcp:pbxdeviceprofiles', href => sprintf("/api/pbxdeviceprofiles/%d", $item->profile_id)),
            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
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
    my @lines;
    for my $line ($item->autoprov_field_device_lines->all) {
        my $p_subs = $line->provisioning_voip_subscriber;
        my $b_subs = $p_subs ? $p_subs->voip_subscriber : undef;
        my $line_attr = { $line->get_inflated_columns };
        foreach my $f(qw/id device_id linerange_id/) {
            delete $line_attr->{$f};
        }
        foreach my $f(qw/key_num/) {
            $line_attr->{$f} = int($line_attr->{$f});
        }
        $line_attr->{subscriber_id} = int($b_subs->id)
            if($b_subs);
        $line_attr->{linerange} = $line->autoprov_device_line_range->name;
        $line_attr->{type} = delete $line_attr->{line_type};
        push @lines, $line_attr;
    }
    $resource{customer_id} = delete $resource{contract_id};

    my $form = $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );
    $resource{lines} = \@lines;
    $resource{id} = int($item->id);
    return \%resource;
}

sub item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_field_devices');

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

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $iden_device = $schema->resultset('autoprov_field_devices')->find({identifier => $resource->{identifier}});
    if($iden_device && $iden_device->id != $item->id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Entry with given 'identifier' already exists.");
        return;
    }

    my $customer_rs = $schema->resultset('contracts')->search({
        id => $resource->{customer_id},
        status => { '!=' => 'terminated' },
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $customer_rs = $customer_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => 'contact',
        });
    }
    my $customer = $customer_rs->first;
    unless($customer) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid customer_id, does not exist.");
        return;
    }
    $resource->{contract_id} = delete $resource->{customer_id};
    
    my $dev_model = $self->model_from_profile_id($c, $resource->{profile_id});
    return unless($dev_model);
    unless($dev_model->reseller_id == $customer->contact->reseller_id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid customer_id and profile_id combination, both must belong to the same reseller.");
        return;
    }

    my @oldlines = $item->autoprov_field_device_lines->all;
    my $i = 0;
    for my $line ( @{$resource->{lines}} ) {
        my $oldline = delete $oldlines[$i++];
        unless ($line->{subscriber_id} && $line->{subscriber_id} > 0) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid line. Invalid 'subscriber_id'.");
            return;
        }
        my $b_subs = $schema->resultset('voip_subscribers')->find($line->{subscriber_id});
        my $p_subs = $b_subs ? $b_subs->provisioning_voip_subscriber : undef;
        unless ($p_subs) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'. Could not find subscriber.");
            return;
        }
        $line->{subscriber_id} = $p_subs->id;
        unless(defined $line->{linerange}) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid line. Invalid 'linerange'.");
            return;
        }
        my $linerange = $dev_model->autoprov_device_line_ranges->find({
            name => $line->{linerange}
        });
        unless($linerange) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'linerange', does not exist.");
            return;
        }
        delete $line->{linerange};
        $line->{linerange_id} = $linerange->id;
        if($line->{key_num} >= $linerange->num_lines) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'key_num', out of range for this linerange.");
            return;
        }

        $line->{line_type} = delete $line->{type};

        if($oldline) {
            $oldline->update($line);
        } else {
            $item->autoprov_field_device_lines->create($line);
        }
    }
    foreach my $oldline(@oldlines) {
        $oldline->delete if($oldline);
    }

    my $lines = delete $resource->{lines};
    my $old_identifier = $item->identifier;
    unless($old_identifier eq $resource->{identifier}) {
        my $err = NGCP::Panel::Utils::DeviceBootstrap::dispatch(
            $c, 'register', $item, $old_identifier
        );
        die $err if $err;
    }
    $item->update($resource);
    
    return $item;
}

sub model_from_profile_id {
    my ($self, $c, $profile_id) = @_;

    my $profile_rs = $c->model('DB')->resultset('autoprov_profiles')->search({
       id => $profile_id,
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $profile_rs = $profile_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    my $profile = $profile_rs->first;
    unless($profile) {
        $c->log->error("failed to find device profile with id 'profile_id'");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Invalid profile_id, device profile does not exist.");
        return;
    }
    my $config = $profile->config;
    unless($config) {
        $c->log->error("device profile with id '" . $profile->id . "' doesn't have a config");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Invalid profile_id, device profile does not have a config.");
        return;
    }
    unless($config->device) {
        $c->log->error("device config id '" . $config->id . "' doesn't have a device model");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Invalid profile_id, device profile config does not have a device model.");
        return;
    }

    return $config->device;
}

1;
# vim: set tabstop=4 expandtab:
