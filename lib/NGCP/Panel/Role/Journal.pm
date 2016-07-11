package NGCP::Panel::Role::Journal;

use Sipwise::Base;

use NGCP::Panel::Utils::Journal;

sub add_create_journal_item_hal {
    my ($self,$c,@args) = @_;
    return NGCP::Panel::Utils::Journal::add_journal_item_hal($self,$c,NGCP::Panel::Utils::Journal::CREATE_JOURNAL_OP,@args);
}

sub add_update_journal_item_hal {
    my ($self,$c,@args) = @_;
    return NGCP::Panel::Utils::Journal::add_journal_item_hal($self,$c,NGCP::Panel::Utils::Journal::UPDATE_JOURNAL_OP,@args);
}

sub add_delete_journal_item_hal {
    my ($self,$c,@args) = @_;
    return NGCP::Panel::Utils::Journal::add_journal_item_hal($self,$c,NGCP::Panel::Utils::Journal::DELETE_JOURNAL_OP,@args);
}

sub get_journal_action_config {
    my ($class,$resource_name,$action_template) = @_;
    my $cfg = NGCP::Panel::Utils::Journal::get_journal_resource_config(NGCP::Panel->config,$resource_name);
    if ($cfg->{journal_resource_enabled}) {
        return NGCP::Panel::Utils::Journal::get_api_journal_action_config('api/' . $resource_name,$action_template,$class->get_journal_methods);
    }
    return [];
}

sub get_journal_query_params {
    my ($class,$query_params) = @_;
    return NGCP::Panel::Utils::Journal::get_api_journal_query_params($query_params);
}

sub handle_item_base_journal {
    return NGCP::Panel::Utils::Journal::handle_api_item_base_journal(@_);
}

sub handle_journals_get {
    return NGCP::Panel::Utils::Journal::handle_api_journals_get(@_);
}

sub handle_journalsitem_get {
    return NGCP::Panel::Utils::Journal::handle_api_journalsitem_get(@_);
}

sub handle_journals_options {
    return NGCP::Panel::Utils::Journal::handle_api_journals_options(@_);
}

sub handle_journalsitem_options {
    return NGCP::Panel::Utils::Journal::handle_api_journalsitem_options(@_);
}

sub handle_journals_head {
    return NGCP::Panel::Utils::Journal::handle_api_journals_head(@_);
}

sub handle_journalsitem_head {
    return NGCP::Panel::Utils::Journal::handle_api_journalsitem_head(@_);
}

sub get_journal_relation_link {
    my $cfg = NGCP::Panel::Utils::Journal::get_journal_resource_config(NGCP::Panel->config,$_[0]->resource_name);
    if ($cfg->{journal_resource_enabled}) {
        return NGCP::Panel::Utils::Journal::get_journal_relation_link(@_);
    }
    return ();
}
1;
