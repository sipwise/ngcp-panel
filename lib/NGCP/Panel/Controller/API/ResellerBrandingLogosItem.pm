package NGCP::Panel::Controller::API::ResellerBrandingLogosItem;
use Sipwise::Base;

use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::ResellerBrandingLogos/;

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

    my $branding = $item->branding;

    if ($branding && $branding->logo) {
        my $data = $branding->logo;
        my $mime_type = $branding->logo_image_type;
        my $fext = $mime_type; 
        $fext =~ s/^.*?([a-zA-Z0-9]+)$/$1/;
        return (\$data, $mime_type, 'reseller_'.$item->id.'_branding_logo.'.$fext);
    }
    else{
        $self->error($c, HTTP_NOT_FOUND, "No branding logo available for this reseller");
        return;
    }
}

1;

# vim: set tabstop=4 expandtab:
