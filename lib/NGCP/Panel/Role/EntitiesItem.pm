package NGCP::Panel::Role::EntitiesItem;

use warnings;
use strict;

use parent qw/Catalyst::Controller/;

use boolean qw(true);
use Safe::Isa qw($_isa);
use Path::Tiny qw(path);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();

sub set_config {
    my $self = shift;
    my $allowed_roles_by_methods = $self->get_allowed_roles();
    $self->config(
        action => {
            map { $_ => {
                ACLDetachTo => '/api/root/invalid_user',
                AllowedRole => $allowed_roles_by_methods->{$_},
                Args => 1,
                Does => [qw(ACL RequireSSL)],
                Method => $_,
                Path => $self->dispatch_path,
                %{$self->_set_config($_)},
            } } @{ $self->allowed_methods }
        },
        @{ $self->get_journal_action_config($self->resource_name,{
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Does => [qw(ACL RequireSSL)],
        }) },
        #action_roles => [qw(HTTPMethods)],
        log_response => 1,
        %{$self->_set_config()},
        #log_response = 0|1 - don't log response body
        #own_transaction_control = {post|put|patch|delete|all => 1|0}
    );
}

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}


sub get {
    my ($self, $c, $id) = @_;
    {
        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;
        my $header_accept = $c->request->header('Accept');
        if(defined $header_accept
            && ($header_accept ne 'application/json')
            && ($header_accept ne '*/*')
        ) {
            $self->return_requested_type($c,$id,$item);
            return;
        }

        my $hal = $self->hal_from_item($c, $item);
        return unless $hal;
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-[a-z]+)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
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
    my $guard = $self->get_transaction_control($c);
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my ($form, $form_exceptions, $process_extras);
        ($form, $form_exceptions) = $self->get_form($c, 'edit');

        my $json = $self->get_valid_patch_data(
            c          => $c,
            id         => $id,
            media_type => 'application/json-patch+json',
            form       => $form,
        );
        last unless $json;

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;
        my $old_resource = $self->resource_from_item($c, $item);
        #$old_resource = clone($old_resource);
        ##without it error: The entity could not be processed: Modification of a read-only value attempted at /usr/share/perl5/JSON/Pointer.pm line 200, <$fh> line 1.\n
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        ($item, $form, $form_exceptions, $process_extras) = $self->update_item($c, $item, $old_resource, $resource, $form, $process_extras );
        last unless $item;

        $self->complete_transaction($c);
        $self->post_process_commit($c, 'patch', $item, $old_resource, $resource, $form, $process_extras);

        $self->return_representation($c,
            'item' => $item,
            'form' => $form,
            'preference' => $preference,
            'form_exceptions' => $form_exceptions
        );
    }
    return;
}

sub put {
    my ($self, $c, $id) = @_;
    my $guard = $self->get_transaction_control($c);
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        #TODO: MOVE form exceptions to proper forms as property
        #$old_resource = clone($old_resource);
        ##without it error: The entity could not be processed: Modification of a read-only value attempted at /usr/share/perl5/JSON/Pointer.pm line 200, <$fh> line 1.\n
        my ($form, $form_exceptions, $process_extras);
        ($form, $form_exceptions) = $self->get_form($c, 'edit');

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;
        my $method_config = $self->config->{action}->{PUT};
        my ($resource, $data) = $self->get_valid_data(
            c          => $c,
            id         => $id,
            method     => 'PUT',
            media_type => $method_config->{ContentType} // 'application/json',
            uploads    => $method_config->{Uploads} // [] ,
            form       => $form,
        );
        last unless $resource;
        my $old_resource = $self->resource_from_item($c, $item);

        ($item, $form, $form_exceptions, $process_extras) = $self->update_item($c, $item, $old_resource, $resource, $form, $process_extras );
        last unless $item;

        $self->complete_transaction($c);
        $self->post_process_commit($c, 'put', $item, $old_resource, $resource, $form, $process_extras);
        $self->return_representation($c,
            'item' => $item,
            'form' => $form,
            'preference' => $preference,
            'form_exceptions' => $form_exceptions
        );
    }
    return;
}


sub delete {
    my ($self, $c, $id) = @_;

    my $guard = $self->get_transaction_control($c);
    {
        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        $self->delete_item($c, $item );

        $self->complete_transaction($c);
        $self->post_process_commit($c, 'delete', $item);

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub delete_item{
    my($self, $c, $item) = @_;
    $item->delete();
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
    if($self->config->{log_response}){
        $self->log_response($c);
    }
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
