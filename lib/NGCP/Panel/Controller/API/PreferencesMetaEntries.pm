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

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $devmod_id = 
    return NGCP::Panel::Utils::Preferences::create_dev_dynamic_preference(
        $c, $resource, devmod => $c->stash->{devmod} 
    );
}
1;

# vim: set tabstop=4 expandtab:
