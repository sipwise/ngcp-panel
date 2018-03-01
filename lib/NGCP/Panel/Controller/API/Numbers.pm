package NGCP::Panel::Controller::API::Numbers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Numbers/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Allows to list and re-assign numbers (primary and aliases) between subscribers in an atomic operation.'
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for numbers assigned to subscribers belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    { join => { 'subscriber' => { 'contract' => 'contact' } } };
                },
            },

        },
        {
            param => 'customer_id',
            description => 'Filter for numbers assigned to subscribers of a specific customer.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'subscriber.contract_id' => $q };
                },
                second => sub {
                    return { join => 'subscriber' };
                },
            },
        },
        {
            param => 'subscriber_id',
            description => 'Filter for numbers assigned to a specific subscriber.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'subscriber_id' => $q };
                },
                second => sub {
                    return { };
                },
            },
        },
        {
            param => 'type',
            description => 'Filter for number type, either "primary" or "alias".',
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
