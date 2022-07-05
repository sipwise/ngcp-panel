package NGCP::Panel::Controller::API::PhonebookEntriesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PhonebookEntries/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    mandatory_parameters => { 'single' => [qw/reseller_id customer_id subscriber_id/],},
    allowed_ngcp_types => [qw/carrier sppro/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

1;

# vim: set tabstop=4 expandtab:
