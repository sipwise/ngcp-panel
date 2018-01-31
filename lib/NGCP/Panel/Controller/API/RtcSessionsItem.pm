package NGCP::Panel::Controller::API::RtcSessionsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;


use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::RtcSessions/;

sub resource_name{
    return 'rtcsessions';
}

sub dispatch_path{
    return '/api/rtcsessions/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-rtcsessions';
}

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriber subscriberadmin/],
        Journal => [qw/admin reseller/],
    }
});





sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, rtc_session => $item);

        my $hal = $self->hal_from_item($c, $item);

        unless ($hal) {
            $c->log->error("Session not found. It may have expired.");
            $self->error($c, HTTP_NOT_FOUND, "Session not found. It may have expired.");
            last;
        }

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r
                =~ s/rel=self/rel="item self"/r;
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
