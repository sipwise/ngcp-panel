package NGCP::Panel::Controller::API::SubscribersItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use Clone qw/clone/;
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::ProfilePackages qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Subscribers/;

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
        DELETE  => [qw/admin reseller ccareadmin ccare subscriberadmin/],
        Journal => [qw/admin reseller ccareadmin ccare/],
    }
});


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
            my $subscriber = $self->item_by_id($c, $id);
            last unless $self->resource_exists($c, subscriber => $subscriber);

            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $subscriber->contract,
                ); #apply underrun lock level


            my ($form) = $self->get_form($c);
            my $resource = $self->resource_from_item($c, $subscriber, $form);
            my $hal = $self->hal_from_item($c, $subscriber, $resource, $form);
            $guard->commit; #potential db write ops in hal_from

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

    return unless $self->check_write_access($c, $id);

    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');
    TX_START:
    $c->clear_errors;
    try {
        my $guard = $schema->txn_scope_guard;
        {
            my $preference = $self->require_preference($c);
            last unless $preference;

            my $subscriber = $self->item_by_id($c, $id);
            last unless $self->resource_exists($c, subscriber => $subscriber);
            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $subscriber->contract,
                ); #apply underrun lock level
            $c->stash->{subscriber} = $subscriber; # password validation
            my $resource = $self->get_valid_put_data(
                c => $c,
                id => $id,
                media_type => 'application/json',
            );
            last unless $resource;
            my $r = $self->prepare_resource($c, $schema, $resource, $subscriber);
            last unless $r;

            $resource = $r->{resource};

            my ($form) = $self->get_form($c);
            $subscriber = $self->update_item($c, $schema, $subscriber, $r, $resource, $form);
            last unless $subscriber;

            $resource = $self->resource_from_item($c, $subscriber, $form);
            my $hal = $self->hal_from_item($c, $subscriber, $resource, $form);
            last unless $self->add_update_journal_item_hal($c,$hal);

            $guard->commit;
            $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
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

    return unless $self->check_write_access($c, $id);

    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');
    TX_START:
    $c->clear_errors;
    try {
        my $guard = $schema->txn_scope_guard;
        {
            my $preference = $self->require_preference($c);
            last unless $preference;

            my $subscriber = $self->item_by_id($c, $id);
            last unless $self->resource_exists($c, subscriber => $subscriber);
            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                    contract => $subscriber->contract,
                ); #apply underrun lock level
            $c->stash->{subscriber} = $subscriber; # password validation
            my $json = $self->get_valid_patch_data(
                c => $c,
                id => $id,
                media_type => 'application/json-patch+json',
                ops => ["add", "replace", "copy", "remove"],
            );
            last unless $json;

            my $patch_mode = 1;
            my ($form) = $self->get_form($c);
            my $old_resource = $self->resource_from_item($c, $subscriber, $form, $patch_mode);
            $old_resource = clone($old_resource);
            my $resource = $self->apply_patch($c, $old_resource, $json);
            last unless $resource;

            my $update = 1;
            my $r = $self->prepare_resource($c, $schema, $resource, $subscriber, $patch_mode);
            last unless $r;
            $resource = $r->{resource};

            $subscriber = $self->update_item($c, $schema, $subscriber, $r, $resource, $form);
            last unless $subscriber;

            $resource = $self->resource_from_item($c, $subscriber, $form);
            my $hal = $self->hal_from_item($c, $subscriber, $resource, $form);
            last unless $self->add_update_journal_item_hal($c,$hal);

            $guard->commit;
            $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
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

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    return unless $self->check_write_access($c, $id);

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $subscriber = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriber => $subscriber);

        if ($subscriber->contract->product->class eq "pbxaccount" && $subscriber->provisioning_voip_subscriber->is_pbx_pilot) {
            my $other_subscriber = $c->model('DB')->resultset('voip_subscribers')->search({
                                        contract_id => $subscriber->contract->id,
                                        status => { '!=' => 'terminated' },
                                        'provisioning_voip_subscriber.is_pbx_pilot' => 0,
                                    }, {
                                        join => 'provisioning_voip_subscriber',
                                    })->first();
            if ($other_subscriber) {
                $self->error($c, HTTP_FORBIDDEN, "Cannot terminate pilot subscriber when other subscribers exists");
                return;
            }
        }

        if($c->user->roles eq "subscriberadmin") {

            my $prov_sub = $subscriber->provisioning_voip_subscriber;
            if($prov_sub->is_pbx_pilot) {
                $self->error($c, HTTP_FORBIDDEN, "Cannot terminate pilot subscriber");
                return;
            }
            if($prov_sub->id == $c->user->id) {
                $self->error($c, HTTP_FORBIDDEN, "Cannot terminate own subscriber");
                return;
            }
            if($prov_sub->account_id != $c->user->account_id) {
                $self->error($c, HTTP_FORBIDDEN, "Invalid subscriber id");
                last;
            }
        }

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            my $contact = $subscriber->contract->contact;
            unless($contact && $contact->reseller_id == $c->user->reseller_id) {
                $self->error($c, HTTP_FORBIDDEN, "subscriber does not belong to reseller");
                last;
            }
        }

        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my ($_form) = $self->get_form($c);
            #my $_subscriber = $self->item_by_id($c, $id);
            my $_resource = $self->resource_from_item($c, $subscriber, $_form);
            return $self->hal_from_item($c,$subscriber,$_resource,$_form); });

        NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);

        $guard->commit;

        try {
            my (undef, $xmlrpc_res) = NGCP::Panel::Utils::Kamailio::trusted_reload($c);
            if (!defined $xmlrpc_res || $xmlrpc_res < 1) {
                die "XMLRPC failed";
            }
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => "failed to reload kamailio: $e. Subscriber was terminated.",
                desc  => $c->loc('Failed to reload kamailio. Subscriber was terminated.'),
            );
        }

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
