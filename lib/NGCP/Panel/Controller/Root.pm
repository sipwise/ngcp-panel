package NGCP::Panel::Controller::Root;
use Sipwise::Base;


BEGIN { extends 'Catalyst::Controller' }

use NGCP::Panel::Widget;
use Scalar::Util qw(blessed);

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

sub auto :Private {
    my($self, $c) = @_;

    $c->log->debug("*** Root::auto called");

    if (
        __PACKAGE__ eq $c->controller->catalyst_component_name
        or 'NGCP::Panel::Controller::Login' eq $c->controller->catalyst_component_name
        or $c->req->uri->path =~ m|^/device/autoprov/.+|
    ) {
        $c->log->debug("*** Root::auto skip authn, grant access to " . $c->request->path);
        return 1;
    }

    if($c->user_exists && $c->user->roles ne "api_admin" &&
       0 == index $c->controller->catalyst_component_name, 'NGCP::Panel::Controller::API') {
        
        $c->log->debug("*** Root::auto invalidate authenticated non-api-admin user for api access");
        $c->logout;
    }

    unless($c->user_exists) {
        $c->log->debug("*** Root::auto user not authenticated");
        if (
            exists $c->request->env->{SSL_CLIENT_M_SERIAL}
            && 0 == index $c->controller->catalyst_component_name, 'NGCP::Panel::Controller::API'
        ) {
            my $ssl_client_m_serial = hex $c->request->env->{SSL_CLIENT_M_SERIAL};
            $c->authenticate({ ssl_client_m_serial => $ssl_client_m_serial }, 'api_admin');
            $c->detach(qw(API::Root invalid_user), [$ssl_client_m_serial]) unless $c->user_exists;
            return 1;
        }
        # don't redirect to login page for ajax uris
        if($c->request->path =~ /\/ajax$/) {
            $c->response->body("403 - Permission denied");
            $c->response->status(403);
            return;
        }
        
        # store uri for redirect after login
        my $target = undef;
        if($c->request->method eq 'GET') {
            if($c->request->uri !~ /\/logout$/) {
                $target = $c->request->uri;
            } else {
                $target = $c->uri_for("/dashboard");
            }
        } else {
            $target = $c->request->headers->referer;
        }
        $c->log->debug("*** Root::auto do login, target='$target'");
        $c->session(target => $target);
        $c->response->redirect($c->uri_for('/login/subscriber'));
        return;
    }

    $c->log->debug("*** Root::auto grant access for authenticated user");

    # check for read_only on write operations
    if($c->user->read_only && (
        $c->req->uri->path =~ /create/
        || $c->req->uri->path =~ /edit/
        || $c->req->uri->path =~ /delete/
    )) {
        $c->detach('/denied_page');
    }

    # load top menu widgets
    my $plugin_finder = NGCP::Panel::Widget->new;
    my $topmenu_templates = [];
    foreach($plugin_finder->instantiate_plugins($c, 'topmenu_widgets')) {
        $_->handle($c);
        push @{ $topmenu_templates }, $_->template; 
    }
    $c->stash(topmenu => $topmenu_templates);


    $c->session->{created_objects} = {} unless(defined $c->session->{created_objects});

    return 1;
}

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->redirect($c->uri_for('/dashboard'));
}

sub back :Path('/back') :Args(0) {
    my ( $self, $c ) = @_;
    my $target;
    my $ref_uri = URI->new($c->req->referer) || $c->uri_for('/dashboard');
    if($c->session->{redirect_targets}) {
        while(@{ $c->session->{redirect_targets} }) {
            $target = shift @{ $c->session->{redirect_targets} };
            last unless($ref_uri->path eq $target->path);
        }
        if(!defined $target || $ref_uri->path eq $target->path) {
            $target = $c->uri_for('/dashboard');
        }
    } else {
        $target = $c->uri_for('/dashboard');
    }
    $c->response->redirect($target);
    $c->detach;
}

sub default :Path {
    my ( $self, $c ) = @_;
    $c->detach( '/error_page' );
}

sub render :ActionClass('RenderView') { }

sub end : Private {
    my ($self, $c) = @_;
    $c->forward('render');
    return;
}

sub _prune_row {
    my ($columns, %row) = @_;
    while (my ($k,$v) = each %row) {
        unless ($k ~~ $columns) {
            delete $row{$k};
            next;
        }
        $row{$k} = $v->datetime if blessed($v) && $v->isa('DateTime');
    }
    return { %row };
}

sub error_page :Private {
    my ($self,$c) = @_;
    
    $c->log->error( 'Failed to find path ' . $c->request->path );
    $c->stash(template => 'error_page.tt');
    #$c->response->body( 'Page not found' );
    $c->response->status(404);
}

sub denied_page :Private {
    my ($self,$c) = @_;
    
    $c->log->error('Access denied to path ' . $c->request->path );
    $c->stash(template => 'denied_page.tt');
    $c->response->status(403);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Root - Root Controller for NGCP::Panel

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 auto

Verify user is logged in.
Check user roles.
Load top menu widgets.

=head2 index

The root page (/)

=head2 default

Standard 404 error page

=head2 end

Attempt to render a view, if needed.

=head2 error_page

should be called if the intended page could not be found (404).

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
