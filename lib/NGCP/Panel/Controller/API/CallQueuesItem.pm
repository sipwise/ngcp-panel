package NGCP::Panel::Controller::API::CallQueuesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallQueues/;

sub resource_name{
    return 'callqueues';
}

sub dispatch_path{
    return '/api/callqueues/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callqueues';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

1;
