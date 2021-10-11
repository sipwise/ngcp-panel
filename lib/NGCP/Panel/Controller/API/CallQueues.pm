package NGCP::Panel::Controller::API::CallQueues;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'The queue of waiting calls per subscriber.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for callqueues of subscribers belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            # we handle that separately/manually in the role
            param => 'number',
            description => 'Filter for callqueues of subscribers with numbers matching the given pattern.',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallQueues/;

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
