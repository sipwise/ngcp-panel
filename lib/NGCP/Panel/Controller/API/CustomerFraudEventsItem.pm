package NGCP::Panel::Controller::API::CustomerFraudEventsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CustomerFraudEvents/;

sub resource_name{
    return 'customerfraudevents';
}
sub dispatch_path{
    return '/api/customerfraudevents/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerfraudevents';
}

sub query_params {
    return [
        {
            param => 'interval',
            description => 'Interval filter. values: day, month. default: month',
        },
    ];
}


__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});





sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, customerfraudevent => $item);

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







1;

# vim: set tabstop=4 expandtab:
