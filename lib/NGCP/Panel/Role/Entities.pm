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
#use Path::Tiny qw(path);
#use TryCatch;
#require Catalyst::ActionRole::ACL;
#require Catalyst::ActionRole::CheckTrailingSlash;
#require Catalyst::ActionRole::HTTPMethods;
#require Catalyst::ActionRole::RequireSSL;


sub set_config {
    my $self = shift;
    $self->config(
        action => {
            map { $_ => {
                ACLDetachTo => '/api/root/invalid_user',
                AllowedRole => [qw/admin reseller/],
                Args => 0,
                Does => [qw(ACL CheckTrailingSlash RequireSSL)],
                Method => $_,
                Path => $self->dispatch_path,
                %{$self->_set_config($_)},
            } } @{ $self->allowed_methods }
        },
        #action_roles => [qw(HTTPMethods)],
        %{$self->_set_config()},
        #log_response = 0|1 - don't log response body
        #own_transaction_control->{PUT|POST|PATCH|DELETE} = 0|1 - don't start transaction guard
    );
}

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub get_list{
    my ($self, $c) = @_;
    return $self->item_rs($c);
}

sub get {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->get_list($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my ($form) = $self->get_form($c);
        my @items = 'ARRAY' eq ref $items ? @$items : $items->all;
        for my $item (@items) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%s', $c->request->path, $self->get_item_id($c, $item)),
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
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type =>  $self->config->{action}->{OPTIONS}->{POST}->{ContentType} // 'application/json',
        );
        last unless $resource;
        #instead of type parameter get_form can check request method
        my ($form, $form_exceptions) = $self->get_form($c, 'add');
        if(!$form_exceptions && $form->can('form_exceptions')){
            $form_exceptions = $form->form_exceptions;
        }
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            $form_exceptions ? (exceptions => $form_exceptions) : (),
        );

        my $process_extras= {};
        last unless $self->process_form_resource($c, undef, undef, $resource, $form, $process_extras);
        last unless $resource;
        last unless $self->check_duplicate($c, undef, undef, $resource, $form, $process_extras);
        last unless $self->check_resource($c, undef, undef, $resource, $form, $process_extras);

        my $item = $self->create_item($c, $resource, $form, $process_extras);

        $self->complete_transaction($c);

        $self->post_process_commit($c, 'create', $item, undef, $resource, $form, $process_extras);
        
        $self->return_representation_post($c, 'item' => $item, 'form' => $form, 'form_exceptions' => $form_exceptions );
    }
    return;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
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
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
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

sub HEAD  {
    my ($self) = shift;
    return $self->head(@_);
}

sub OPTIONS  {
    my ($self) = shift;
    return $self->options(@_);
}

sub POST {
    my ($self) = shift;
    return $self->post(@_);
}

1;

# vim: set tabstop=4 expandtab:
