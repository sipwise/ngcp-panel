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

##### --------- common part

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    if ($self->config->{log_request}) {
        $self->log_request($c);
    }
    return 1;
}

sub end :Private {
    my ($self, $c) = @_;
    if ($self->config->{log_response}) {
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
        #own_transaction_control->{PUT|POST|PATCH|DELETE|ALL} = 0|1 - don't start transaction guard in parent classes, implementation need to control it
        #ReturnContentType => 'binary'#mostly for GET. value different from 'application/json' says that method is going to return binary data using get_item_binary_data
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
        ( 'item' eq $params->{interface_type}
        ?
            @{ $self->get_journal_action_config($self->resource_name,{
                ACLDetachTo => '/api/root/invalid_user',
                AllowedRole => $allowed_roles_by_methods->{'Journal'},
                Does => [qw(ACL RequireSSL)],
            }) }
        : 
            () ),
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
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my ($form) = $self->get_form($c);
        my @items = 'ARRAY' eq ref $items ? @$items : $items->all;
        for my $item (@items) {
            push @embedded, $self->hal_from_item($c, $item, $form, {});
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%s', $c->request->path, $self->get_item_id($c,
                    $item, undef, undef, { purpose => 'hal_links_href' })),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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
    my $guard = $self->get_transaction_control($c);
    {
       my ($form) = $self->get_form($c, 'add');
        my $method_config = $self->config->{action}->{POST};
        my $process_extras= {};
        my ($resource) = $self->get_valid_data(
            c               => $c,
            method          =>  'POST',
            media_type      =>  $method_config->{ContentType} // 'application/json',
            uploads         => $method_config->{Uploads} // [] ,
            form            => $form,
        );
        last unless $resource;
        #instead of type parameter get_form can check request method
        last unless $self->pre_process_form_resource($c, undef, undef, $resource, $form, $process_extras);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        last unless $self->process_form_resource($c, undef, undef, $resource, $form, $process_extras);
        last unless $resource;
        last unless $self->check_duplicate($c, undef, undef, $resource, $form, $process_extras);
        last unless $self->check_resource($c, undef, undef, $resource, $form, $process_extras);

        my $item = $self->create_item($c, $resource, $form, $process_extras);
        last unless $item;

        $self->complete_transaction($c);

        $self->post_process_commit($c, 'create', $item, undef, $resource, $form, $process_extras);

        return if defined $c->stash->{api_error_message};

        $self->return_representation_post($c, 'item' => $item, 'form' => $form );
    }
    return;
}


sub POST {
    my ($self) = shift;
    return $self->post(@_);
}

1;

# vim: set tabstop=4 expandtab:
