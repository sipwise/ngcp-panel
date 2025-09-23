package NGCP::Panel::Controller::API::CallListsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::API::Calllist;

use NGCP::Panel::Utils::ValidateJSON qw();
use DateTime::TimeZone;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallLists/;

sub resource_name{
    return 'calllists';
}

sub dispatch_path{
    return '/api/calllists/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-calllists';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub query_params {
    return [
        {
            param => 'subscriber_id',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                if ($c->user->roles ne "subscriber") {
                    my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($q);
                    if ($subscriber) {
                        my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            source_user_id => $subscriber->uuid,
                        }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
                        my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            destination_user_id => $subscriber->uuid,
                            source_user_id => { '!=' => $subscriber->uuid },
                        }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);
                        return $out_rs->union_all($in_rs);
                    }
                }
                return $rs;
            },
        },
        {
            param => 'customer_id',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                if ($c->user->roles ne "subscriber" and $c->user->roles ne "subscriberadmin" and not exists $c->req->query_params->{subscriber_id}) {
                    my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            source_account_id => $q,
                    }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
                    my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            destination_account_id => $q,
                            source_account_id => { '!=' => $q },
                    }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);
                    return $out_rs->union_all($in_rs);
                }
                return $rs;
            },
        },
    ],
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {

        my $schema = $c->model('DB');
        last unless $self->valid_id($c, $id);

        my $owner = NGCP::Panel::Utils::API::Calllist::get_owner_data($self, $c, $schema);
        $c->stash(owner => $owner);
        last unless $owner;
        my $form = $self->get_form($c);
        my $href_data = $owner->{subscriber} ?
            "subscriber_id=".$owner->{subscriber}->id :
            "customer_id=".$owner->{customer}->id;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, calllist => $item);

        my $hal = $self->hal_from_item($c, $item, $form, { 'owner' => $owner });

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
