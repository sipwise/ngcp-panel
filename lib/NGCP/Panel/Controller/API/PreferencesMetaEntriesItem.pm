package NGCP::Panel::Controller::API::PreferencesMetaEntriesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use NGCP::Panel::Utils::Preferences;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PreferencesMetaEntries/;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    }
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub item_name{
    return 'preferencesmetaentry';
}

sub resource_name{
    return 'preferencesmetaentries';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
} 

sub update_item_model{
    my($self, $c, $item, $old_resource, $resource, $form, $process_extras) = @_;
    NGCP::Panel::Utils::Preferences::update_dynamic_preference(
        $c, $item, $resource,
        
    );
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
