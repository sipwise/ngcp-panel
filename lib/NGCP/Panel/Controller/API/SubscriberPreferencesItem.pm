package NGCP::Panel::Controller::API::SubscriberPreferencesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Preferences/;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::ProfilePackages qw();

__PACKAGE__->set_config({
    PATCH => { ops => [qw/add replace remove copy/] },
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
        Journal => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
    },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

sub resource_name{
    return 'subscriberpreferences';
}

sub container_resource_type{
    return 'subscribers';
}

sub dispatch_path{
    return '/api/subscriberpreferences/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberpreferences';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    TX_START:
    $c->clear_errors;
    try {
        my $guard = $c->model('DB')->txn_scope_guard;
        {
            last unless $self->valid_id($c, $id);
            my $subscriber = $self->item_by_id($c, $id, "subscribers");
            last unless $self->resource_exists($c, subscriberpreference => $subscriber);

            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $subscriber->contract,
                ); #apply underrun lock level
            my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
            $guard->commit; #potential db write ops in hal_from

            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                (map { # XXX Data::HAL must be able to generate links with multiple relations
                    s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r
                    =~ s/rel=self/rel="item self"/r;
                } $hal->http_headers),
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->body($response->content);
            return;
        }
    } catch($e) {
        if ($self->check_deadlock($c, $e)) {
            goto TX_START;
        }
        unless ($c->has_errors) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error', $e);
            last;
        }
    }
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    TX_START:
    $c->clear_errors;
    try {
        my $guard = $c->model('DB')->txn_scope_guard;
        {
            my $preference = $self->require_preference($c);
            last unless $preference;

            my $json = $self->get_valid_patch_data(
                c => $c,
                id => $id,
                media_type => 'application/json-patch+json',
                ops => [qw/add replace remove copy/],
            );
            last unless $json;

            my $subscriber = $self->item_by_id($c, $id, "subscribers");
            last unless $self->resource_exists($c, subscriberpreferences => $subscriber);
            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $subscriber->contract,
                ); #apply underrun lock level

            my $old_resource = $self->get_resource($c, $subscriber, "subscribers");
            my $resource = $self->apply_patch($c, $old_resource, $json);
            last unless $resource;

            # last param is "no replace" to NOT delete existing prefs
            # for proper PATCH behavior
            $subscriber = $self->update_item($c, $subscriber, $old_resource, $resource, 0, "subscribers");
            last unless $subscriber;

            my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
            last unless $self->add_update_journal_item_hal($c,$hal);

            $guard->commit;

            if ('minimal' eq $preference) {
                $c->response->status(HTTP_NO_CONTENT);
                $c->response->header(Preference_Applied => 'return=minimal');
                $c->response->body(q());
            } else {
                #my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
                my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                    $hal->http_headers,
                ), $hal->as_json);
                $c->response->headers($response->headers);
                $c->response->header(Preference_Applied => 'return=representation');
                $c->response->body($response->content);
            }
        }
    } catch($e) {
        if ($self->check_deadlock($c, $e)) {
            goto TX_START;
        }
        unless ($c->has_errors) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error', $e);
            last;
        }
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    TX_START:
    $c->clear_errors;
    try {
        my $guard = $c->model('DB')->txn_scope_guard;
        {
            my $preference = $self->require_preference($c);
            last unless $preference;

            my $subscriber = $self->item_by_id($c, $id, "subscribers");
            last unless $self->resource_exists($c, systemcontact => $subscriber);
            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $subscriber->contract,
                ); #apply underrun lock level
            my $resource = $self->get_valid_put_data(
                c => $c,
                id => $id,
                media_type => 'application/json',
            );
            last unless $resource;
            my $old_resource = $self->get_resource($c, $subscriber, "subscribers");

            # last param is "replace" to delete all existing prefs
            # for proper PUT behavior
            $subscriber = $self->update_item($c, $subscriber, $old_resource, $resource, 1, "subscribers");
            last unless $subscriber;

            my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
            last unless $self->add_update_journal_item_hal($c,$hal);

            $guard->commit;

            if ('minimal' eq $preference) {
                $c->response->status(HTTP_NO_CONTENT);
                $c->response->header(Preference_Applied => 'return=minimal');
                $c->response->body(q());
            } else {
                #my $hal = $self->hal_from_item($c, $subscriber, "subscribers");
                my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                    $hal->http_headers,
                ), $hal->as_json);
                $c->response->headers($response->headers);
                $c->response->header(Preference_Applied => 'return=representation');
                $c->response->body($response->content);
            }
        }
    } catch($e) {
        if ($self->check_deadlock($c, $e)) {
            goto TX_START;
        }
        unless ($c->has_errors) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error', $e);
            last;
        }
    }
    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
