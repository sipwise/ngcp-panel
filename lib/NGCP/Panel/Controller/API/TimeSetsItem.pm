package NGCP::Panel::Controller::API::TimeSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::TimeSets/;

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    },
    PATCH => { ops => [qw/add replace remove copy/] },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
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
