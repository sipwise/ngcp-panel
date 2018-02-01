package NGCP::Panel::Controller::API::SystemContactsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SystemContacts/;

sub resource_name{
    return 'systemcontacts';
}
sub dispatch_path{
    return '/api/systemcontacts/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-systemcontacts';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->config(
    action => {
        (map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }),
        @{ __PACKAGE__->get_journal_action_config(__PACKAGE__->resource_name,{
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => 'admin',
            Does => [qw(ACL RequireSSL)],
        }) }
    },
);





sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);

        my $hal = $self->hal_from_contact($c, $contact);

        # TODO: we don't need reseller stuff here!
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}





sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);
        my $old_resource = { $contact->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $contact = $self->update_contact($c, $contact, $old_resource, $resource, $form);
        last unless $contact;

        my $hal = $self->hal_from_contact($c, $contact, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $contact->get_inflated_columns };

        my $form = $self->get_form($c);
        $contact = $self->update_contact($c, $contact, $old_resource, $resource, $form);
        last unless $contact;

        my $hal = $self->hal_from_contact($c, $contact, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $contact = $self->contact_by_id($c, $id);
        last unless $self->resource_exists($c, systemcontact => $contact);
        my $contract_rs = $c->model('DB')->resultset('contracts')->search({
            contact_id => $id,
            status => { '!=' => 'terminated' },
        });
        my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            contact_id => $id,
            status => { '!=' => 'terminated' },
        }); # hypotecial, but for the sake of symmetry with customer contacts
        if ($contract_rs->first or $subscriber_rs->first) { #2. if active contracts or subscribers -> error
            $self->error($c, HTTP_LOCKED, "Contact is still in use.");
            last;
        } else {
            $contract_rs = $c->model('DB')->resultset('contracts')->search({
                contact_id => $id,
                status => { '=' => 'terminated' },
            });
            $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
                contact_id => $id,
                status => { '=' => 'terminated' },
            }); # hypotecial, but for the sake of symmetry with customer contacts
            if ($contract_rs->first or $subscriber_rs->first) { #1. terminate if terminated contracts or subscribers
                $c->log->debug("terminate contact id ".$contact->id);
                try {
                    $contact->update({
                        status => "terminated",
                        terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local,
                    });
                    $contact->discard_changes();
                } catch($e) {
                    $c->log->error("Failed to terminate contact id '".$contact->id."': $e");
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error.");
                    last;
                };
                my $form = $self->get_form($c);
                my $hal = $self->hal_from_contact($c, $contact, $form);
                last unless $self->add_update_journal_item_hal($c,$hal);
            } else { #3. delete otherwise
                last unless $self->add_delete_journal_item_hal($c,sub {
                    my $self = shift;
                    my ($c) = @_;
                    my $_form = $self->get_form($c);
                    return $self->hal_from_contact($c, $contact, $_form); });
                $c->log->debug("delete contact id ".$contact->id);
                $contact->delete;
            }
        }
        $guard->commit;

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
