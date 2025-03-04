package NGCP::Panel::Role::Entities;

use warnings;
use strict;
use parent qw/Catalyst::Controller/;
use boolean qw(true);
use Safe::Isa qw($_isa);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use Data::HAL qw();
use Data::HAL::Link qw();
use TryCatch;

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

    if (my $accept = $c->request->header('Accept')) {
        if ($accept eq 'application/json') {
            $c->response->content_type($accept);
        }
    }

    $self->log_response($c);

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
        #ContentType         => ['multipart/form-data'],#allowed REQUEST content type
        #ResourceContentType => 'native' for request_params for csv upload cases to avoid default upload behavior when resource is taken from multipart/form-data {json} body part
        #Uploads             => [qw/front_image mac_image/],#uploads filenames
        #  or
        #Uploads             => {'greetingfile' => ['audio/x-wav', 'application/octet-stream']},
        #'backward_allow_empty_upload' => [0}1], #default 0. For backward compatibility, when we allowed faxes data input as json field, but not as file
        #own_transaction_control->{PUT|POST|PATCH|DELETE|ALL} = 0|1 - don't start transaction guard in parent classes, implementation need to control it
        #ReturnContentType => 'binary'#mostly for GET. value different from 'application/json' says that method is going to return binary data using get_item_binary_data
        #'dont_validate_hal' => [0|1], #default 0. Apply or not hal resource validation through form. Validation can be avoided if no PUT or PATCH method supposed for "information" collections
        #'no_item_created' => [0|1], #default 0. For rare case when we create something asyronously
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

sub options {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    my $post_allowed = grep { $_ eq 'POST' } @{ $allowed_methods };
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
#        $post_allowed
#        ? (
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
#        ) : (),
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub get {
    my ($self, $c) = @_;
    my $header_accept = $c->request->header('Accept');
    if(defined $header_accept && ($header_accept eq 'text/csv')) {
        $self->return_csv($c);
        return;
    }
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->get_list($c);
        return unless $items;
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my ($form) = $self->get_form($c);
        $self->expand_collection_fields($c, \@embedded);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form, {});
            push @links, grep { $_->relation->_original eq 'ngcp:'.$self->resource_name } @{$embedded[-1]->links};
        }
        $self->expand_collection_fields($c, \@embedded);
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef,
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub post {
    my ($self) = shift;
    my ($c) = @_;

    my $method_config = $self->get_config('action')->{POST};
    my $process_extras= {};
    my ($resource, $item, $form, $hal, $hal_id);

    TX_START:
    try {
        $c->clear_errors;
        $form = $self->get_form($c, 'add');

        my $guard = $self->start_transaction($c);
        {
            my ($data, $non_json_data);
            ($resource, $data, $non_json_data) = $self->get_valid_data(
                c                   => $c,
                method              => 'POST',
                media_type          => $method_config->{ContentType} // 'application/json',
                uploads             => $method_config->{Uploads} // [] ,
                form                => $form,
                resource_media_type => $method_config->{ResourceContentType},
            );
            unless ($resource) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Could not validate request data',
                             '#get_valid_data') unless $c->has_errors;
                goto TX_END;
            }

            if (!$non_json_data || !$data) {
                delete $resource->{purge_existing};

                unless ($self->pre_process_form_resource($c, undef, undef, $resource, $form, $process_extras)) {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Could not validate request data',
                                 '#pre_process_form_resource') unless $c->has_errors;
                    goto TX_END;
                }

                return unless $self->validate_form(
                    c => $c,
                    resource => $resource,
                    form => $form,
                );

                unless ($self->process_form_resource($c, undef, undef, $resource, $form, $process_extras)) {
                    if ($c->has_errors) {
                        goto TX_END;
                    }
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Could not validate request data',
                                 '#pre_process_form_resource') unless $c->has_errors;
                    goto TX_END;
                }

                unless ($self->check_duplicate($c, undef, undef, $resource, $form, $process_extras)) {
                    if ($c->has_errors) {
                        goto TX_END;
                    }
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Could not validate request data',
                                 '#check_duplicates') unless $c->has_errors;
                    goto TX_END;
                }

                unless ($self->check_resource($c, undef, undef, $resource, $form, $process_extras)) {
                    if ($c->has_errors) {
                        goto TX_END;
                    }
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'Could not validate request data',
                                 '#check_resource') unless $c->has_errors;
                    goto TX_END;
                }

                $item = $self->create_item($c, $resource, $form, $process_extras);
                if ($c->has_errors) {
                    goto TX_END;
                }
                unless ($item || $self->get_config('no_item_created')) {
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error',
                                 '#create_item') unless $c->has_errors;
                    goto TX_END;
                }

                ($hal, $hal_id) = $self->get_journal_item_hal($c, $item, { form => $form });
                unless ($self->add_journal_item_hal($c, { hal => $hal, ($hal_id ? ( id => $hal_id, ) : ()) })) {
                    if ($c->has_errors) {
                        goto TX_END;
                    }
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error',
                                 '#add_journal_item_hal') unless $c->has_errors;
                    goto TX_END;
                }
            } else {
                try {
                    #$processed_ok(array), $processed_failed(array), $info, $error
                    my $data_processed_result = $self->process_data(
                        c        => $c,
                        data     => \$data,
                        resource => $resource,
                        form     => $form,
                        process_extras => $process_extras,
                    );
                } catch($e) {
                    $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                                 "failed to process non json data", $e);
                    return;
                };
            }
            $self->commit_transaction($c, $guard);
        }

        TX_END:
        if ($c->has_errors) { # something went wrong without triggering an exception
            $self->check_deadlock($c, $c->last_error) and goto TX_START;
            return;
        }
    } catch($e) {
        $self->check_deadlock($c, $e) and goto TX_START;
        unless ($c->has_errors) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, 'Internal Server Error', $e);
        }
        return;
    }

    $self->post_process_commit($c, 'create', $item, undef, $resource, $form, $process_extras);

    return if $c->has_errors;

    $self->return_representation_post($c,
        'hal'  => $hal,
        'item' => $item,
        'form' => $form
    );

    return;
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $rs = $self->_item_rs($c);
    return unless $rs;
    my $item = $rs->create($resource);
    return $item;
}

sub POST {
    my ($self) = shift;
    return $self->post(@_);
}

1;

# vim: set tabstop=4 expandtab:
