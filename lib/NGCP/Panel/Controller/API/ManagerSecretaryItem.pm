package NGCP::Panel::Controller::API::ManagerSecretaryItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PUT DELETE/];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::ManagerSecretary/;

sub resource_name{
    return 'managersecretary';
}
sub dispatch_path{
    return '/api/managersecretary/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-managersecretary';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->config(
    action => {
        (map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }),
        @{ __PACKAGE__->get_journal_action_config(__PACKAGE__->resource_name,{
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Does => [qw(ACL RequireSSL)],
        }) }
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        last unless $self->valid_uuid($c, $id);
        my $item = $self->item_by_uuid($c, $id);
        last unless $self->resource_exists($c, 'managersecretary' => $item);

        if ($preference eq 'internal') {
            $c->response->status(HTTP_OK);
            $c->response->header(Preference_Applied => 'return=internal');
            $c->response->body($self->json_from_item($c, $item));
        } else {
            my $hal = $self->hal_from_item($c, $item);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                (map { # XXX Data::HAL must be able to generate links with multiple relations
                    s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r
                    =~ s/rel=self/rel="item self"/r;
                } $hal->http_headers),
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->body($response->content);
        }
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_uuid($c, $id);
        last unless $self->resource_exists($c, managersecretary => $item);

        my ($hal, $form, $old_resource, $resource);

        unless ($preference eq 'internal') {
            $form = $self->get_form($c);
        }

        $item = $self->update_item($c, $item, $old_resource, $resource, $form, $preference);
        unless ($item) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update manager secretary callforward.");
            last;
        }

        unless ($preference eq 'internal') {
            $hal = $self->hal_from_item($c, $item);
            last unless $self->add_update_journal_item_hal($c,{ hal => $hal, id => $id });
        }

        $guard->commit;

        if ('internal' eq $preference) {
            $c->response->status(HTTP_OK);
            $c->response->header(Preference_Applied => 'return=internal');
            $c->response->body(q());
        } elsif ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_uuid($c, $id);
        last unless $self->resource_exists($c, managersecretary => $item);

        my ($form, $old_resource, $resource);

        if ($preference ne 'internal') {
            $form = $self->get_form($c);

            last unless $self->add_delete_journal_item_hal($c,{ hal_from_item => sub {
                my $self = shift;
                my ($c) = @_;
                return $self->hal_from_item($c, $item); },
                id => $id});
        }

        try {
            $item = $self->update_item($c, $item, $old_resource, $resource, $form, $preference);
        } catch($e) {
            $c->log->error("Failed to delete manager secretary callforward with id '$id': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
            last;
        }

        $guard->commit;

        if ('internal' eq $preference) {
            $c->response->status(HTTP_OK);
            $c->response->header(Preference_Applied => 'return=internal');
            $c->response->body(q());
        } else {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->body(q());
        }
    }
    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
