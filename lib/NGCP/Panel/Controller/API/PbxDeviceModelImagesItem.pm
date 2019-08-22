package NGCP::Panel::Controller::API::PbxDeviceModelImagesItem;
use Sipwise::Base;

use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxDeviceModelImages NGCP::Panel::Role::API::PbxDeviceModels/;

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    GET => {
        ReturnContentType => 'binary',
    },
    log_response  => 0,
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub get_item_binary_data{
    my($self, $c, $id, $item) = @_;
    my $type = $c->req->param('type') // 'front';
    my $data;
    my $mime_type;
    if($type eq 'mac') {
        $data = $item->mac_image;
        $mime_type = $item->mac_image_type;
    } elsif($type eq 'front_thumb') {
        $data = $item->front_thumbnail;
        $mime_type = $item->front_thumbnail_type;
        unless (defined $data) {
            $data = $item->front_image;
            $mime_type = $item->front_image_type;
        }
    } else {
        $data = $item->front_image;
        $mime_type = $item->front_image_type;
    }
    unless(defined $data) {
        $self->error($c, HTTP_NOT_FOUND, "Image type '$type' is not uploaded");
        return;
    }

    my $fext = $mime_type; 
    $fext =~ s/^.*?([a-zA-Z0-9]+)$/$1/;
    my $filename = $item->vendor . ' ' . $item->model . ".$fext";
    return (\$data, $mime_type, $filename);
}

1;

# vim: set tabstop=4 expandtab:
