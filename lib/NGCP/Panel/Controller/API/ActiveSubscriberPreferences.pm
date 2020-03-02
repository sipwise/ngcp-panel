package NGCP::Panel::Controller::API::ActiveSubscriberPreferences;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#subscribers">Subscriber</a>. The full list of properties can be obtained via <a href="/api/subscriberpreferencedefs/">SubscriberPreferenceDefs</a>.';
};

sub container_resource_type{
    return 'active';
}

sub resource_name{
    return 'activesubscriberpreferences';
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for subscribers of customers belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    { join => { 'contract' => 'contact' } };
                },
            },
        },
        {
            param => 'contact_id',
            description => 'Filter for subscribers of contracts with a specific contact id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contract.contact_id' => $q };
                },
                second => sub {},
            },
        },
    ];
}
1;

# vim: set tabstop=4 expandtab:
