package NGCP::Panel::Controller::API::FaxserverSettings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::FaxserverSettings/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriber subscriberadmin/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies faxserver settings for a specific subscriber.';
}

sub query_params {
    return [
        {
            param => 'name_or_password',
            description => 'Filter for items (subscribers) where name or password field match given pattern',
            query => {
                first => sub {
                    my $q = shift;
                    return { '-or' => [
                            { 'voip_fax_preference.name' => { like => $q } },
                            { 'voip_fax_preference.password' => { like => $q } },
                        ] };
                },
                second => sub {
                    return { prefetch => { 'provisioning_voip_subscriber' => 'voip_fax_preference' } };
                },
            },
        },
        {
            param => 'active',
            description => 'Filter for items (subscribers) with active faxserver settings',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        { 'voip_fax_preference.active' => 1 };
                    } else {
                        {};
                    }
                },
                second => sub {
                    { prefetch => { 'provisioning_voip_subscriber' => 'voip_fax_preference' } };
                },
            },
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
