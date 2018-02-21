package NGCP::Panel::Controller::API::NumbersItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Numbers/;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin/],
        Journal => [qw/admin reseller/],
    }
});

sub allowed_methods{
    return [qw/GET PUT PATCH OPTIONS HEAD/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head handle_journalsitem_put handle_journalsitem_patch/];
}   

1;

# vim: set tabstop=4 expandtab:
