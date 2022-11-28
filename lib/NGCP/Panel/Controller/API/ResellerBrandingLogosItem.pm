package NGCP::Panel::Controller::API::ResellerBrandingLogosItem;
use Sipwise::Base;

use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::ResellerBrandingLogos/;

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    log_response  => 0,
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub GET :Allow {
    my($self, $c, $id) = @_;

    my $item = $self->item_by_id($c, $id);

    unless ($item && $item->logo && $item->logo_image_type) {
        $self->error($c, HTTP_NOT_FOUND, "ResellerBrandingLogo is not found or does not have image/image_type");
        return;
    }

    $c->response->content_type($item->logo_image_type);
    $c->response->body($item->logo);
}

1;

# vim: set tabstop=4 expandtab:
