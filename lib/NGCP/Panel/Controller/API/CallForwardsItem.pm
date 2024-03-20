package NGCP::Panel::Controller::API::CallForwardsItem;
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

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallForwards/;

sub resource_name{
    return 'callforwards';
}

sub dispatch_path{
    return '/api/callforwards/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callforwards';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
        Journal => [qw/admin reseller subscriberadmin subscriber/],
    }
});

sub delete_item {
    my ($self, $c, $item) = @_;

    my $id = $item->id;

    try {
        my $form = $self->get_form($c);
        my $old_resource = undef;
        my $resource = {};
        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        return $item;
    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                     "Failed to delete callforward with id '$id'", $e);
        last;
    }

    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
