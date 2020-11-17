package NGCP::Panel::Controller::API::ResellerBrandingLogos;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ResellerBrandingLogos/;

__PACKAGE__->set_config();

sub config_allowed_roles {
    return [qw/admin reseller subscriberadmin subscriber/];
}

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Used to download the reseller branding logo image. Returns a binary attachment with the correct content type (e.g. image/jpeg) of the image.';
};

sub GET :Allow {
    my ($self, $c) = @_;
    my $item = $self->item_rs($c);

    unless($c->req->param('subscriber_id')) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "subscriber_id parameter is mandatory.");
        return;
    }

    unless($item->first) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber_id. Subscriber not found.");
        return;
    }

    my $branding = $item->first->branding;

    unless($branding || $branding->logo) {
        $self->error($c, HTTP_NOT_FOUND, "No branding logo available for this reseller");
        return;
        return;
    }
    $c->response->content_type($branding->logo_image_type);
    $c->response->body($branding->logo);
}

1;

# vim: set tabstop=4 expandtab:
