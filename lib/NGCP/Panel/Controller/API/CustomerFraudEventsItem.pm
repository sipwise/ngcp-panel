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
    return [qw/GET OPTIONS HEAD PATCH/];
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

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

1;
