package NGCP::Panel::Controller::API::PbxDeviceProfilePreferencesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    PATCH => { ops => [qw/add replace remove copy/] },
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    },
    required_licenses => [qw/pbx device_provisioning/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

sub item_name{
    return 'pbxdeviceprofilepreference';
}

sub resource_name{
    return 'pbxdeviceprofilepreferences';
}

sub container_resource_type{
    return 'pbxdeviceprofiles';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
} 



1;

# vim: set tabstop=4 expandtab:
