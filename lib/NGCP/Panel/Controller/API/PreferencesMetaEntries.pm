package NGCP::Panel::Controller::API::PreferencesMetaEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use NGCP::Panel::Utils::Preferences;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PreferencesMetaEntries/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD POST/];
}

sub item_name{
    return 'preferencesmetaentry';
}

sub resource_name{
    return 'preferencesmetaentries';
}

sub api_description {
    return 'Preferences meta information management.';
};

sub query_params {
    return [
        {
            param => 'attribute',
            description => 'Filter for dynamic preference with a specific name',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.attribute' => NGCP::Panel::Utils::Preferences::dynamic_pref_attribute_to_db($q)};
                },
                second => sub { },
            },
        },
        {
            param => 'model_id',
            description => 'Filter for dynamic preference relevant to the spcified pbx device model id',
            query => {
                first => sub {
                    my $q = shift;
                    { 
                        '-or' => [
                                'voip_preference_relations.autoprov_device_id' => $q,
                                'voip_preference_relations.voip_preference_id' => undef
                            ],
                    };
                },
                second => sub { 
                    { 
                        join => {'voip_preferences' => 'voip_preference_relations'},
                    }
                },
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for dynamic preference relevant to the spcified reseller id',
            query => {
                first => sub {
                    my $q = shift;
                    { 
                        '-or' => [
                                'autoprov_devices.reseller_id' => $q,
                                'voip_preference_relations.reseller_id' => $q,
                                'voip_preference_relations.voip_preference_id' => undef
                            ],
                    };
                },
                second => sub { 
                    {
                        #left join for the 
                        join => {'voip_preferences' => { 'voip_preference_relations' => 'autoprov_devices' } },
                    }
                },
            },
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $preference = NGCP::Panel::Utils::Preferences::create_dynamic_preference(
        $c, 
        $resource, 
        group_name => 'CPBX Device Administration',
    );
    return $preference;
}
1;

# vim: set tabstop=4 expandtab:
