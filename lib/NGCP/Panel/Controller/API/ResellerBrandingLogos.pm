package NGCP::Panel::Controller::API::ResellerBrandingLogos;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ResellerBrandingLogos/;

__PACKAGE__->set_config({
    log_response  => 0,
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Download the reseller branding logo image. Returns a binary data with the correct content-type (e.g. image/jpeg) of the image.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for logos that belong to the reseller of the subscriber',
            new_rs => sub {
                my ($c, $q, $rs) = @_;
                return $rs->search_rs({
                    'voip_subscribers.id' => $c->req->param('subscriber_id')
                },{
                    join => { 'reseller' => { 'contacts' => { 'contracts' => 'voip_subscribers' } } }
                });
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for logos that belong to the reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.reseller_id' => $q };
                },
                second => sub {},
            },
        },
    ];
}

sub GET :Allow {
    my ($self, $c) = @_;

    if ($c->user->roles eq 'admin') {
        if (!$c->req->param('subscriber_id') && !$c->req->param('reseller_id')) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "'reseller_id' or 'subscriber_id' parameter is mandatory.");
            return;
        }
    }

    my $item = $self->item_rs($c)->first;

    unless ($item && $item->logo && $item->logo_image_type) {
        $self->error($c, HTTP_NOT_FOUND, "ResellerBrandingLogo is not found or does not have image/image_type");
        return;
    }

    $c->response->content_type($item->logo_image_type);
    $c->response->body($item->logo);
}

1;

# vim: set tabstop=4 expandtab:
