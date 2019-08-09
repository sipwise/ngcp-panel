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
    return 'Defines a list of current fraud limit violations (the threshold for outgoing call costs per day/month was exceeded) of customers.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for fraud events belonging to a specific reseller',
        },
        {
            param => 'contract_id',
            description => 'Filter for fraud events of a specific contract',
        },
        {
            param => 'interval',
            description => 'Interval filter. values: ["day", "month"].',
        },
        {
            param => 'notify_status',
            description => 'Notify status filter. values: ["new", "notified"].',
        },
    ];
}

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'customer_id' => 'customer_id',
        'id' => 'id',
        'interval' => 'interval',
        'notified_at' => 'notified_at',
        'notify_status' => 'notify_status',
        'reseller_id' => 'reseller_id',
    };
    return $cols;
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