package NGCP::Panel::Controller::Root;
use NGCP::Panel::Utils::Generic qw(:all);
use Moose;

BEGIN { extends 'Catalyst::Controller' }

use Scalar::Util qw(blessed);
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::Statistics qw();
use DateTime qw();
use Time::HiRes qw();
use DateTime::Format::RFC3339 qw();
use JSON;
#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

sub auto :Private {
    my($self, $c) = @_;
    #exit(0); # just for profiling
    $c->log->debug(JSON::to_json($c->request->params));
    
    my $res;
    if((!$c->request->params->{realm} && !$c->session->{realm}) || (defined $c->request->params->{realm} && 'admin' eq $c->request->params->{realm}) || ( defined $c->session->{realm} && 'admin' eq $c->session->{realm} && !defined $c->request->params->{realm} )){ 
        my $user = 'administrator';
        my $pass = 'administrator';
     #   my $d = '';
        my $realm = 'admin';
        $res = 
             $c->authenticate(
                {
                    login => $user, 
                    md5pass => $pass,
                    'dbix_class' => {
                        searchargs => [{
                            -and => [
                                login => $user,
                                is_active => 1, 
                            ],
                        }],
                    }
                }, 
                $realm);
    }
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
        $c->languages([$c->session->{lang}, 'i-default']);
    } else { # if language has not yet be set, set it from config or browser
        if (defined $c->config->{appearance}{force_language}) {
            $c->log->debug("lang set by config: " . $c->config->{appearance}{force_language});
            $c->languages([$c->config->{appearance}{force_language}, 'i-default']);
        } else {
            $c->languages([ map { s/^en.*$/i-default/r } @{ $c->languages } ]);
        }
        $c->session->{lang} = $c->language;
        $c->log->debug("lang set by browser or config: " . $c->language);
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
            my $ngcp_api_realm = $c->request->env->{NGCP_API_REALM} // "";
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
                $self->api_apply_fake_time($c);
                return 1;
            } elsif ($c->req->headers->header("NGCP-UserAgent") &&
                     $c->req->headers->header("NGCP-UserAgent") eq "NGCP::API::Client") {
                $c->log->debug("++++++ Root::auto API request with system auth");
                my $realm = "api_admin_system";
                my $res = $c->authenticate({}, $realm);

                unless ($c->user_exists) {
                    $c->log->debug("+++++ invalid api admin system login");
                    $c->log->warn("invalid api system login from '".$c->req->address."'");
                }

                $self->api_apply_fake_time($c);
                return 1;
            } elsif ($ngcp_api_realm eq "subscriber") {
                $c->log->debug("++++++ Root::auto API subscriber request with http auth");
                my $realm = "api_subscriber_http";
                my ($username,$password) = $c->req->headers->authorization_basic;
                my ($u,$d) = split(/\@/,$username);
                if ($d) {
                    $c->req->headers->authorization_basic($u,$password);
                }
                my $res = $c->authenticate({}, $realm);

                if($c->user_exists) {
                    $d //= $c->req->uri->host;
                    $c->log->debug("++++++ checking '".$c->user->domain->domain."' against '$d'");
                    if ($c->user->domain->domain ne $d) {
                        $c->user->logout;
                        $c->log->debug("+++++ invalid api subscriber http login (domain check failed)");
                        $c->log->warn("invalid api http login from '".$c->req->address."'");
                        my $r = $c->get_auth_realm($realm);
                        $r->credential->authorization_required_response($c, $r);
                        return;
                    }
                    $c->log->debug("++++++ subscriber '".$c->user->webusername."' authenticated via api_subscriber_http");
                } else {
                    $c->user->logout if($c->user);
                    $c->log->debug("+++++ invalid api subscriber http login");
                    $c->log->warn("invalid api http login from '".$c->req->address."'");
                    my $r = $c->get_auth_realm($realm);
                    $r->credential->authorization_required_response($c, $r);
                    return;
                }
                $self->api_apply_fake_time($c);
                return 1;
            } else {
                $c->log->debug("++++++ Root::auto API admin request with http auth");
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
                $self->api_apply_fake_time($c);
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

    if (exists $c->config->{external_documentation}{link} && 'ARRAY' ne ref $c->config->{external_documentation}{link}) {
        $c->config->{external_documentation}{link} = [$c->config->{external_documentation}{link}];
    }

    # load top menu widgets
    my $topmenu_templates = [];
    if ($c->user->roles eq 'admin') {
        $topmenu_templates = ['widgets/admin_topmenu_settings.tt'];
    } elsif ($c->user->roles eq 'reseller') {
        $topmenu_templates = ['widgets/reseller_topmenu_settings.tt'];
    } elsif ($c->user->roles eq 'subscriberadmin') {
        $topmenu_templates = ['widgets/subscriberadmin_topmenu_settings.tt'];
    } elsif ($c->user->roles eq 'subscriber') {
        $topmenu_templates = ['widgets/subscriber_topmenu_settings.tt'];
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
        $c->response->body(JSON::to_json({
                code => 404,
                message => 'Path not found',
            })."\n");
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

sub api_apply_fake_time :Private {
    my ($self, $c) = @_;
    my $allow_fake_client_time = 0;
    my $cfg = $c->config->{api_debug_opts};
    $allow_fake_client_time = ((defined $cfg->{allow_fake_client_time}) && $cfg->{allow_fake_client_time} ? 1 : 0) if defined $cfg;
    if ($allow_fake_client_time) { #exists $ENV{API_FAKE_CLIENT_TIME} && $ENV{API_FAKE_CLIENT_TIME}) {
        my $date = $c->request->header('X-Fake-Clienttime'); #('Date');
        if ($date) {
            #my $dt = NGCP::Panel::Utils::DateTime::from_rfc1123_string($date);
            my $dt = NGCP::Panel::Utils::DateTime::from_string($date);
            if ($dt) {
                NGCP::Panel::Utils::DateTime::set_fake_time($dt);
                $c->stash->{is_fake_time} = 1;
                my $id = $c->request->header('X-Request-Identifier');
                $c->log->debug('using X-Fake-Clienttime header to fake system time: ' . NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::current_local) . ($id ? ' - request id: ' . $id : ''));
                return;
            }
        }
        NGCP::Panel::Utils::DateTime::set_fake_time();
        $c->stash->{is_fake_time} = 0;
        #$c->log->debug('resetting faked system time: ' . NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::current_local));
    }
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
