package NGCP::Panel::Controller::API::CFTimeSetsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CFTimeSets/;

sub resource_name{
    return 'cftimesets';
}

sub dispatch_path{
    return '/api/cftimesets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cftimesets';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
        Journal => [qw/admin reseller ccareadmin ccare/],
    },
    PATCH => { ops => [qw/add replace remove copy/] },
});

sub delete_item {
    my ($self, $c, $item) = @_;

    return unless $self->check_subscriber_can_update_item($c, $item);

    try {
        $item->delete;
    } catch($e) {
        my $id = $item->id;
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                     "Failed to delete cftimeset with id '$id'", $e);
        return;
    }

    return 1;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
