package NGCP::Panel::Controller::API::CFBNumberSetsItem;
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

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CFBNumberSets/;

sub resource_name{
    return 'cfbnumbersets';
}

sub dispatch_path{
    return '/api/cfbnumbersets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cfbnumbersets';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin subscriber/],
        Journal => [qw/admin reseller/],
    },
    PATCH => { ops => [qw/add replace remove copy/] },
});

# sub PATCH :Allow {
#     last unless $self->add_update_journal_item_hal($c,$hal);
# }

# sub PUT :Allow {
#     last unless $self->add_update_journal_item_hal($c,$hal);
# }

# sub DELETE :Allow {
#         last unless $self->add_delete_journal_item_hal($c,sub {
#             my $self = shift;
#             my ($c) = @_;
#             return $self->hal_from_item($c, $sset); });
# }

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
