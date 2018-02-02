package NGCP::Panel::Controller::API::Calls;
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
    return 'Defines calls placed or received by a customer.';
};

sub query_params {
    return [
        {
            param => 'customer_id',
            description => 'Filter for calls of a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    {
                        -or => [
                            { source_account_id => $q },
                            { destination_account_id => $q },
                        ],
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'subscriber_id',
            description => 'Filter for calls of a specific subscriber',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($q);
                if ($subscriber) {
                    my $out_rs = $rs->search_rs({
                        source_user_id => $subscriber->uuid,
                    });
                    my $in_rs = $rs->search_rs({
                        destination_user_id => $subscriber->uuid,
                        source_user_id => { '!=' => $subscriber->uuid },
                    });
                    return $out_rs->union_all($in_rs);
                }
                return $rs;
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Calls/;

sub resource_name{
    return 'calls';
}

sub dispatch_path{
    return '/api/calls/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-calls';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});



1;

# vim: set tabstop=4 expandtab:
