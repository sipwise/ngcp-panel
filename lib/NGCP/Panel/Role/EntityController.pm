package NGCP::Panel::Role::EntityController;

use warnings;
use strict;

use boolean qw(true);
use Safe::Isa qw($_isa);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use Data::Dumper;
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

    if (!defined $params->{interface_type}) {
        if (__PACKAGE__ =~/Item$/) {
            $params->{interface_type} = 'item';
        } elsif (__PACKAGE__ =~/PreferenceDefs$/) {
            $params->{interface_type} = 'preferencedefs';
        } else {
            $params->{interface_type} = 'collection';
        }
    }

    $params->{resource_name} //= $self->resource_name;
    if (!defined $params->{resource_name}) {
        $params->{resource_name} = lc __PACKAGE__;
        $params->{resource_name} =~s/::([^:]+)(?:item)$/$1/;
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

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    if($self->config->{log_request}){
        $self->log_request($c);
    }
}

sub head {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub options {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    my $post_allowed = grep { $_ eq 'POST' } @{ $allowed_methods };
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        $post_allowed 
        ? ( 
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
        ) : (),
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

sub HEAD  {
    my ($self) = shift;
    return $self->head(@_);
}

sub OPTIONS  {
    my ($self) = shift;
    return $self->options(@_);
}

1;

# vim: set tabstop=4 expandtab:
