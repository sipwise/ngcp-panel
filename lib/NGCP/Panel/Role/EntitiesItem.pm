package NGCP::Panel::Role::EntitiesItem;

use parent qw/Catalyst::Controller/;

use boolean qw(true);
use Safe::Isa qw($_isa);
use Path::Tiny qw(path);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use Data::HAL qw();
use Data::HAL::Link qw();
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();

sub set_config {
    my $self = shift;
    $self->config(
        action => {
            map { $_ => {
                ACLDetachTo => '/api/root/invalid_user',
                AllowedRole => [qw/admin reseller/],
                Args => 1,
                Does => [qw(ACL RequireSSL)],
                Method => $_,
                Path => $self->dispatch_path,
                %{$self->_set_config($_)},
            } } @{ $self->allowed_methods }
        },
        action_roles => [qw(HTTPMethods)],
        %{$self->_set_config()},
    );
}

sub get {
    my ($self, $c, $id) = @_;
    {
        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        my $hal = $self->hal_from_item($c, $item);

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

sub patch {
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

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;
        my $old_resource = { $item->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form;
        ($item,$form) = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;

        $guard->commit;
        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
    }
    return;
}

sub put {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => $self->config->{action}->{OPTIONS}->{PUT}->{ContentType} // 'application/json',
        );
        last unless $resource;
        my $old_resource = { $item->get_inflated_columns };
        my $form;
        
        ($item, $form) = $self->update_item($c, $item, $old_resource, $resource, $form );
        last unless $item;

        $guard->commit;

        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
    }
    return;
}


sub delete {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        $self->delete_item($c, $item );
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub head {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub options {
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

sub end :Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

sub GET {
    my ($self) = shift;
    return $self->get(@_);
}

sub HEAD {
    my ($self) = shift;
    return $self->head(@_);
}

sub OPTIONS  {
    my ($self) = shift;
    return $self->options(@_);
}

sub PUT {
    my ($self) = shift;
    return $self->put(@_);
}

sub PATCH {
    my ($self) = shift;
    return $self->patch(@_);
}

sub DELETE {
    my ($self) = shift;
    return $self->delete(@_);
}

1;

# vim: set tabstop=4 expandtab:
