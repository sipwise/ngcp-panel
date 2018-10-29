package NGCP::Panel::Role::EntitiesItem;

use warnings;
use strict;

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

##### --------- common part

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    if ($self->get_config('log_request')) {
        $self->log_request($c);
    }
    return $self->validate_request($c);
}

sub end :Private {
    my ($self, $c) = @_;
    if ($self->get_config('log_response')) {
        $self->log_response($c);
    }
    return 1;
}

sub GET {
    my ($self) = shift;
    return $self->get(@_);
}

sub HEAD  {
    my ($self) = shift;
    return $self->head(@_);
}

sub OPTIONS  {
    my ($self) = shift;
    return $self->options(@_);
}

sub set_config {
    my $self = shift;
    my ($params) = @_;
    $params //= {};
    #Global => {
        #resource_name
        #item_name
        #allowed_roles
        #allowed_methods
        #log_response
        #log_request
    #}
    #AllMethods | METHOD => {
        #AllowedRole
        #ACLDetachTo
        #Args
        #Does
        #DoesAdd
        #Method
        #Path
        #ContentType => ['multipart/form-data'],#allowed REQUEST content type
        #Uploads     => [qw/front_image mac_image/],#uploads filenames
        #  or
        #Uploads     => {'greetingfile' => ['audio/x-wav', 'application/octet-stream']},
        #'backward_allow_empty_upload' => [0}1], #default 0. For backward compatibility, when we allowed faxes data input as json field, but not as file

        #own_transaction_control->{PUT|POST|PATCH|DELETE|ALL} = 0|1 - don't start transaction guard in parent classes, implementation need to control it
        #ReturnContentType => 'binary'#mostly for GET. value different from 'application/json' says that method is going to return binary data using get_item_binary_data
        #'dont_validate_hal' => [0|1], #default 0. Apply or not hal resource validation through form. Validation can be avoided if no PUT or PATCH method supposed for "information" collections
        #'no_item_created' => [0|1], #default 0. For rare case when we create something asynchronously
    #}

    my $obj_name = $self;
    if (!defined $params->{interface_type}) {
        if ($obj_name =~/Item$/) {
            $params->{interface_type} = 'item';
        } elsif ($obj_name =~/PreferenceDefs$/) {
            $params->{interface_type} = 'preferencedefs';
        } else {
            $params->{interface_type} = 'collection';
        }
    }

    $params->{resource_name} //= $self->resource_name;
    if (!defined $params->{resource_name}) {
        $params->{resource_name} = lc $obj_name;
        $params->{resource_name} =~s/.*?::([^:]+)$/$1/;
        $params->{resource_name} =~s/item$//;
    }

    $params->{item_name} //= $self->item_name;
    if (!defined $params->{item_name}) {
        $params->{item_name} = $params->{resource_name};
        $params->{item_name} =~s/s$//;
    }

    my $params_all_methods = delete $params->{AllMethods} // {};

    my $allowed_roles_by_methods = $self->get_allowed_roles(delete $params->{allowed_roles});
    my $params_action_add = delete $params->{action_add} // {};
    my $config_action = {
        (map {
            my $params_method = delete $params->{$_} // {};
            $_ => {
                ACLDetachTo => '/api/root/invalid_user',
                AllowedRole => $allowed_roles_by_methods->{$_},
                Args => ( $params->{interface_type} eq 'item' ? 1 : 0 ),
                Does => [
                    'ACL',
                    ( $params->{interface_type} eq 'item' ? () : ('CheckTrailingSlash') ),
                    'RequireSSL',
                    ( ref $params_all_methods->{DoesAdd} eq 'ARRAY' ? @$params_all_methods->{DoesAdd} : () ),
                    ( ref $params_method->{DoesAdd} eq 'ARRAY' ? @$params_method->{DoesAdd} : () ),
                ],
                Method => $_,
                Path => $self->dispatch_path($params->{resource_name}),
                ReturnContentType => 'application/json',
                %{$params_all_methods},
                %{$params_method},
        } } @{ $self->allowed_methods }),
        ( 'item' eq $params->{interface_type}
        ?
            @{ $self->get_journal_action_config($self->resource_name,{
                ACLDetachTo => '/api/root/invalid_user',
                AllowedRole => $allowed_roles_by_methods->{'Journal'},
                Does => [qw(ACL RequireSSL)],
            }) }
        :
            () ),
        %{$params_action_add},
    };
    #$config_action = {
    #    %{$config_action},
    #    %{$self->_set_config('AllMethods', $config_action)},
    #};
    #$config_action = {
    #    %{$config_action},
    #    map {
    #        %{$self->_set_config($_, $config_action)},
    #    } } @{ $self->allowed_methods },
    #};
    my $config = {
        action => $config_action,
        log_response => 1,
        log_request  => 1,
        %{$params},
    };
    #$config = {
    #    %{$config},
    #Global to don't pass undefined method and initiate it every time in the _set_config
    #    %{$self->_set_config('Global')},
    #};
    $self->config($config);
}

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub head {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

##### --------- /common part

sub get {
    my ($self, $c, $id) = @_;
    {
        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        my $header_accept = $c->request->header('Accept');
        my $mime_type_from_query_params = $self->mime_type_from_query_params($c);
        my $action_config = $self->get_config('action');
        my $config_allowed_types = $action_config->{GET}->{ReturnContentType};
        my $apllication_json = 'application/json';
        #TODO: to method
        if( ( defined $header_accept
                && ($header_accept !~ m!\bapplication/json\b!)
                && ($header_accept !~ m#(?<![^\s;,])\*/\*(?![^\s;,])#) # application/json OR */*
            )
            || defined $mime_type_from_query_params
            #no header Accept passed, check configured return type
            || ( $config_allowed_types
                && (
                    ( ( !ref $config_allowed_types) 
                        && $config_allowed_types ne $apllication_json)
                    || ( ref $config_allowed_types eq 'ARRAY' 
                         && !grep { $_ eq  $apllication_json } @{ $config_allowed_types } )
                )
            )
            
        ) {
            my $return_type;
            if ($header_accept && $header_accept =~/\*\/\*/ && $mime_type_from_query_params) {
                $return_type = $mime_type_from_query_params;
            } else {
                $return_type = $header_accept // $mime_type_from_query_params;
            }
            
            if ($return_type) {
                return unless $self->check_return_type($c, $return_type, $config_allowed_types);
            } elsif (!ref $config_allowed_types) {
                $return_type = $config_allowed_types;
            }
            $self->return_requested_type($c, $id, $item, $return_type);
            # in case this method is not defined, we should return a reasonable error explaining the Accept Header
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

        my ($form, $process_extras);
        ($form) = $self->get_form($c, 'edit');

        my $method_config =  $self->get_config('action')->{PATCH};
        my $patch_ops = ref $method_config eq 'HASH' && defined $method_config->{ops} ? $method_config->{ops} : [qw/replace copy/];
        my $json = $self->get_valid_patch_data(
            c          => $c,
            id         => $id,
            media_type => 'application/json-patch+json',
            form       => $form,
            ops        => $patch_ops,
        );
        last unless $json;

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;
        my $old_resource = $self->resource_from_item($c, $item);
        #$old_resource = clone($old_resource);
        ##without it error: The entity could not be processed: Modification of a read-only value attempted at /usr/share/perl5/JSON/Pointer.pm line 200, <$fh> line 1.\n
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        ($item, $form, $process_extras) = $self->update_item($c, $item, $old_resource, $resource, $form, $process_extras );
        last unless $item;

        my $hal = $self->get_journal_item_hal($c, $item, { form => $form });
        last unless $self->add_journal_item_hal($c, { hal => $hal });

        $self->complete_transaction($c);
        $self->post_process_commit($c, 'patch', $item, $old_resource, $resource, $form, $process_extras);

        $self->return_representation($c,
            'item' => $item,
            'form' => $form,
            #hal may be empty if we don't need it for journal. 
            #Then it will be taken from item and form
            'hal'  => $hal,
            'preference' => $preference,
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

        #$old_resource = clone($old_resource);
        ##without it error: The entity could not be processed: Modification of a read-only value attempted at /usr/share/perl5/JSON/Pointer.pm line 200, <$fh> line 1.\n
        my ($form, $process_extras);
        ($form) = $self->get_form($c, 'edit');

        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;
        my $method_config = $self->get_config('action')->{PUT};
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

        ($item, $form, $process_extras) = $self->update_item($c, $item, $old_resource, $resource, $form, $process_extras );
        last unless $item;

        my $hal = $self->get_journal_item_hal($c, $item, { form => $form });
        last unless $self->add_journal_item_hal($c, { hal => $hal });

        $self->complete_transaction($c);
        $self->post_process_commit($c, 'put', $item, $old_resource, $resource, $form, $process_extras);
        $self->return_representation($c,
            #hal may be empty if we don't need it for journal. 
            #Then it will be taken from item and form
            'hal'  => $hal,
            'item' => $item,
            'form' => $form,
            'preference' => $preference,
        );
    }
    return;
}

sub delete {  ## no critic (ProhibitBuiltinHomonyms)
    my ($self, $c, $id) = @_;

    my $guard = $self->get_transaction_control($c);
    {
        my $item = $self->item_by_id_valid($c, $id);
        last unless $item;

        my $hal = $self->get_journal_item_hal($c, $item);
        #here we left space for information that checking failed and we decided not to delete item
        if ($self->delete_item($c, $item)) {
            $self->add_journal_item_hal($c, { hal => $hal });
        }

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
    return 1;
}

sub options {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    my $patch_allowed = grep { $_ eq 'PATCH' } @{ $allowed_methods };
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        $patch_allowed
        ? (
        Accept_Patch => 'application/json-patch+json',
        ) : (),
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
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
