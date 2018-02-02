package NGCP::Panel::Controller::API::CustomerFraudEvents;
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
    return 'Defines a list of customers with fraud limits above defined thresholds for a specific interval.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for fraud events belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    return { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'interval',
            description => 'Interval filter. values: day, month. default: month',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerFraudEvents/;

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

# vim: set tabstop=4 expandtab:
