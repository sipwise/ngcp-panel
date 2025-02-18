package NGCP::Panel::Controller::API::PbxUsers;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxUsers/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Returns subscribers with PBX related info.';
};

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
    },
});

sub query_params {
    return [
        {
            param => 'primary_number',
            description => 'Filter for subscribers of contracts with a specific primary number pattern',
            query => {
                first => sub {
                    my ($q,$is_pattern) = escape_search_string_pattern(shift,0,1,1);
                    { \['concat(primary_number.cc, primary_number.ac, primary_number.sn) like ?', $q ] };

                },
                second => sub {
                    return { join => 'primary_number' }
                },
            },
        },
        {
            param => 'pbx_extension',
            description => 'Filter for subscribers of contracts with a specific PBX extension',
            query => {
                first => sub {
                    my ($q,$is_pattern) = escape_search_string_pattern(shift,0,1,1);
                    { 'provisioning_voip_subscriber.pbx_extension' => { like => $q } };

                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' }
                },
            },
        },
        {
            param => 'display_name',
            description => 'Filter for subscribers of contracts with a specific display name',
            query => {
                first => sub {
                    my ($q,$is_pattern) = escape_search_string_pattern(shift);
                    {
                        'attribute.attribute' => 'display_name',
                        'voip_usr_preferences.value' => { like => $q }
                    };

                },
                second => sub {
                    return { join => { 'provisioning_voip_subscriber' => { 'voip_usr_preferences' => 'attribute' } } }
                },
            },
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
