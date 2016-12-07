package NGCP::Panel::Role::API::PbxDeviceModelImages;


use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::API::Validate;

use TryCatch;
use File::Type;

sub item_name {
    return 'pbxdevicemodelimage';
}

sub resource_name{
    return 'pbxdevicemodelimages';
}

sub dispatch_path{
    return '/api/pbxdevicemodelimages/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodelimages';
}

sub get_form {
    my ($self, $c) = @_;
    return;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('autoprov_devices');
    if($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    }
    return $item_rs;
}

sub check_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    $process_extras //= {};
    return unless NGCP::Panel::Utils::API::Validate::check_autoprov_device_id($self, $c, $item->id, $process_extras);
    return 1;
}

sub process_form_resource{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $type = delete $resource->{type};
    $type //= $c->req->param('type') // 'front';

    my $ft = File::Type->new();
    my $content_type = $ft->mime_type(${$process_extras->{binary_ref}});
    if($type eq 'mac') {
        $resource->{mac_image} = ${$process_extras->{binary_ref}};
        $resource->{mac_image_type} = $content_type;
    } else {
        $resource->{front_image} = ${$process_extras->{binary_ref}};
        $resource->{front_image_type} = $content_type;
    }
    return unless($resource);
    return $resource;
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    my $model = $process_extras->{model};
    try {
        $item = $model->update($resource);
    } catch($e) {
        $c->log->error("failed to update device model: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to  update device mode.");
        last;
    }
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
