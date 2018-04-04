package NGCP::Panel::Controller::API::FaxesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Subscriber;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Faxes/;

sub resource_name{
    return 'faxes';
}

sub dispatch_path{
    return '/api/faxes/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-faxes';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, fax => $item);

        my $hal = $self->hal_from_item($c, $item);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}







#sub DELETE :Allow {
#    my ($self, $c, $id) = @_;
#
#    my $guard = $c->model('DB')->txn_scope_guard;
#    {
#        my $item = $self->item_by_id($c, $id);
#        last unless $self->resource_exists($c, fax => $item);
#
#        $item->delete;
#        NGCP::Panel::Utils::Subscriber::vmnotify( 'c' => $c, 'fax' => $item );
#        $guard->commit;
#
#        $c->response->status(HTTP_NO_CONTENT);
#        $c->response->body(q());
#    }
#    return;
#}

1;

# vim: set tabstop=4 expandtab:
