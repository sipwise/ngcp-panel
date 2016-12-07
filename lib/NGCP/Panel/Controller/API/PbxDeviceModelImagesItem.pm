package NGCP::Panel::Controller::API::PbxDeviceModelImagesItem;

use parent qw/NGCP::Panel::Role::EntitiesFilesItem NGCP::Panel::Role::API::PbxDeviceModelImages/;


use Sipwise::Base;
use HTTP::Status qw(:constants);

__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PUT/];
}

sub _set_config{
    my ($self, $method) = @_;
    $method //='';
    if ('PUT' eq $method){
        return { 'ContentType' => 'image/jpeg' };
    }
    return {};
}

sub get_item_file {
    my ($self, $c, $id, $item) = @_;
    

    my $type = $c->req->param('type') // 'front';
    my $data;
    my $ctype;
    if($type eq 'mac') {
        $data = $item->mac_image;
        $ctype = $item->mac_image_type;
    } else {
        $data = $item->front_image;
        $ctype = $item->front_image_type;
    }
    unless(defined $data) {
        $self->error($c, HTTP_NOT_FOUND, "Image type '$type' is not uploaded");
        last;
    }

    my $fext = $ctype; 
    $fext =~ s/^.*?([a-zA-Z0-9]+)$/$1/;
    my $fname = $item->vendor . ' ' . $item->model . ".$fext";
    return $fname,$ctype,$data;
}


1;

# vim: set tabstop=4 expandtab:
