package NGCP::Panel::Controller::Root;
use Sipwise::Base;
BEGIN { extends 'Catalyst::Controller' }
use DateTime qw();
use DateTime::Format::RFC3339 qw();
use NGCP::Panel::Widget;
use Scalar::Util qw(blessed);
use Time::HiRes qw();

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

sub auto :Private {
    my($self, $c) = @_;

    $c->log->debug("*** Root::auto called");

    if(defined $c->request->params->{lang} && $c->request->params->{lang} =~ /^\w+$/) {
        $c->log->debug("checking language");
        if($c->request->params->{lang} eq "en") {
            $c->log->debug("setting language ".$c->request->params->{lang}." to default");
            $c->request->params->{lang} = "i-default";
        }
        if(exists $c->installed_languages->{$c->request->params->{lang}} ||
           $c->request->params->{lang} eq "i-default") {
            $c->session->{lang} = $c->request->params->{lang};
            $c->response->cookies->{ngcp_panel_lang} = { value => $c->request->params->{lang}, expires =>  '+3M', };
            $c->log->debug("Setting language to ". $c->request->params->{lang});
        }
    }
    if (defined $c->session->{lang}) {
        $c->languages([$c->session->{lang}, "i-default"]);
    } elsif ( $c->req->cookie('ngcp_panel_lang') ) {
        $c->session->{lang} = $c->req->cookie('ngcp_panel_lang')->value;
    } else {
        $c->languages([ map { s/^en.*$/i-default/r } @{ $c->languages } ]);
        $c->session->{lang} = $c->language;
    }

    if (
        __PACKAGE__ eq $c->controller->catalyst_component_name
        or 'NGCP::Panel::Controller::Login' eq $c->controller->catalyst_component_name
        or $c->req->uri->path =~ m|^/device/autoprov/.+|
        or $c->req->uri->path =~ m|^/pbx/directory/.+|
        or $c->req->uri->path =~ m|^/recoverwebpassword/?$|
        or $c->req->uri->path =~ m|^/resetwebpassword/?$|
    ) {
        $c->log->debug("*** Root::auto skip authn, grant access to " . $c->request->path);
        return 1;
    }

    unless($c->user_exists) {
       
        if(index($c->controller->catalyst_component_name, 'NGCP::Panel::Controller::API') == 0) {
            $c->log->debug("++++++ Root::auto unauthenticated API request");
            my $ssl_dn = $c->request->env->{SSL_CLIENT_M_DN} // ""; 
            my $ssl_sn = hex ($c->request->env->{SSL_CLIENT_M_SERIAL} // 0);
            if($ssl_sn) {
                $c->log->debug("++++++ Root::auto API request with client auth sn '$ssl_sn'");
                unless($ssl_dn eq "/CN=Sipwise NGCP API client certificate") {
                    $c->log->error("++++++ Root::auto API request with invalid client DN '$ssl_dn'");
                    $c->res->status(403);
                    $c->res->body(JSON::to_json({
                        message => "Invalid client certificate DN '$ssl_dn'",
                        code => 403,
                    }));
                    return;
                }

                my $res = $c->authenticate({ 
                        ssl_client_m_serial => $ssl_sn,
                        is_active => 1, # TODO: abused as password until NoPassword handler is available
                    }, 'api_admin_cert');
                unless($c->user_exists)  {
                    $c->log->warn("invalid api login from '".$c->req->address."'");
                    $c->detach(qw(API::Root invalid_user), [$ssl_sn]) unless $c->user_exists;
                } else {
                    $c->log->debug("++++++ admin '".$c->user->login."' authenticated via api_admin_cert");
                }
                if($c->user->read_only && !($c->req->method =~ /^(GET|HEAD|OPTIONS)$/)) {
                    $c->log->error("invalid method '".$c->req->method."' for read-only user '".$c->user->login."', rejecting");
                    $c->user->logout;
                    $c->response->status(403);
                    $c->res->body(JSON::to_json({
                        message => "Invalid HTTP method for read-only user",
                        code => 403,
                    }));
                    return;
                }
                return 1;


            } else {
                $c->log->debug("++++++ Root::auto API request with http auth");
                my $realm = "api_admin_http";
                my $res = $c->authenticate({}, $realm);

                unless($c->user_exists && $c->user->is_active)  {
                    $c->user->logout if($c->user);
                    $c->log->debug("+++++ invalid api admin http login");
                    $c->log->warn("invalid api http login from '".$c->req->address."'");
                    my $r = $c->get_auth_realm($realm);
                    $r->credential->authorization_required_response($c, $r);
                    return;
                } else {
                    $c->log->debug("++++++ admin '".$c->user->login."' authenticated via api_admin_http");
                }
                if($c->user->read_only && !($c->req->method =~ /^(GET|HEAD|OPTIONS)$/)) {
                    $c->log->error("invalid method '".$c->req->method."' for read-only user '".$c->user->login."', rejecting");
                    $c->user->logout;
                    $c->response->status(403);
                    $c->res->body(JSON::to_json({
                        message => "Invalid HTTP method for read-only user",
                        code => 403,
                    }));
                    return;
                }
                return 1;
            }
        }

        # don't redirect to login page for ajax uris
        if($c->request->path =~ /\/ajax$/ || $c->request->path =~ /ngcpelastic/) {
            $c->response->body($c->loc("403 - Permission denied"));
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
        $c->response->redirect($c->uri_for('/login'));
        return;
    }

    $c->log->debug("*** Root::auto grant access for authenticated user");

    # check for read_only on write operations
    if($c->user->read_only && (
        $c->req->uri->path =~ /create/
        || $c->req->uri->path =~ /edit/
        || $c->req->uri->path =~ /delete/
        || !($c->req->method =~ /^(GET|HEAD|OPTIONS)$/)
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

sub end :Private {
    my ($self, $c) = @_;
    $c->forward('render');
    if (@{ $c->error }) {
        my $incident = DateTime->from_epoch(epoch => Time::HiRes::time);
        my $incident_id = sprintf '%X', $incident->strftime('%s%N');
        my $incident_timestamp = DateTime::Format::RFC3339->new->format_datetime($incident);
        $c->log->error("fatal error, id=$incident_id, timestamp=$incident_timestamp, error=".join(q(), @{ $c->error }));
        $c->clear_errors;
        $c->stash(
            exception_incident => $incident_id,
            exception_timestamp => $incident_timestamp,
            template => 'error_page.tt'
        );
        $c->response->status(500);
        $c->detach($c->view);
    }
}

sub _prune_row {
    my ($columns, %row) = @_;
    while (my ($k,$v) = each %row) {
        unless (grep { $k eq $_ } @$columns) {
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
   
    if($c->request->path =~ /^api\/.+/) {
        $c->response->content_type('application/json');
        $c->response->body(JSON::to_json({ code => 404, message => 'Path not found' })."\n");
    } else {
        $c->stash(template => 'notfound_page.tt');
    }
    $c->response->status(404);
}

sub denied_page :Private {
    my ($self,$c) = @_;
    
    $c->log->error('Access denied to path ' . $c->request->path );
    if($c->request->path =~ /^api\/.+/) {
        $c->response->content_type('application/json');
        $c->response->body(JSON::to_json({ code => 403, message => 'Path forbidden' })."\n");
    } else {
        $c->stash(template => 'denied_page.tt');
    }
    $c->response->status(403);
}

sub emptyajax :Chained('/') :PathPart('emptyajax') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        aaData => [],
        iTotalDisplayRecords => 0,
        iTotalRecords => 0,
        sEcho => $c->request->params->{sEcho} // 1,
    );
    $c->detach( $c->view("JSON") );
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
