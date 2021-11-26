package NGCP::Panel::Controller::Root;
use NGCP::Panel::Utils::Generic qw(:all);

use warnings;
use strict;

use parent 'Catalyst::Controller';

use Scalar::Util qw(blessed);
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::Statistics qw();
use NGCP::Panel::Utils::Auth;
use NGCP::Panel::Form qw();
use DateTime qw();
use Time::HiRes qw();
use DateTime::Format::RFC3339 qw();
use HTTP::Status qw(:constants);
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;
use Data::Entropy::Algorithms qw/rand_bits/;

use NGCP::Schema qw//;

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');


sub auto :Private {
    my($self, $c) = @_;

    $c->stash->{_request_start} = Time::HiRes::time;

    my $is_api_request = 0;
    $c->log->debug("*** New " . $c->request->method . " request on path: /" . $c->request->path);
    if ($c->request->path =~/^api\//i) {
        $c->log->debug("Root::auto enable cache");
        NGCP::Panel::Form::dont_use_cache(0);
        $is_api_request = 1;
    } else {
        $c->log->debug("Root::auto disable cache");
        NGCP::Panel::Form::dont_use_cache(1);
    }

    if ($is_api_request) {
        $self->_handle_api_lang($c);
    } else {
        $self->_handle_ui_lang($c);
    }

    ################################################### timezone retrieval
    if (not $is_api_request and $c->user_exists) {
        if ($c->session->{user_tz}) {
            # nothing to do
        } elsif ($c->user->roles eq 'admin') {
            my $reseller_id = $c->user->reseller_id;
            my $tz_row = $c->model('DB')->resultset('reseller_timezone')->find({reseller_id => $reseller_id});
            _set_session_tz_from_row($c, $tz_row, 'admin', $reseller_id);
        } elsif($c->user->roles eq 'reseller') {
            my $reseller_id = $c->user->reseller_id;
            my $tz_row = $c->model('DB')->resultset('reseller_timezone')->find({reseller_id => $reseller_id});
            _set_session_tz_from_row($c, $tz_row, 'reseller', $reseller_id);
        } elsif($c->user->roles eq 'subscriberadmin') {
            my $contract_id = $c->user->account_id;
            my $tz_row = $c->model('DB')->resultset('contract_timezone')->find({contract_id => $contract_id});
            _set_session_tz_from_row($c, $tz_row, 'subscriberadmin', $contract_id);
        } elsif($c->user->roles eq 'subscriber') {
            my $uuid = $c->user->uuid;
            my $tz_row = $c->model('DB')->resultset('voip_subscriber_timezone')->find({uuid => $uuid});
            _set_session_tz_from_row($c, $tz_row, 'subscriber', $uuid);
        } elsif ($c->user->roles eq 'ccareadmin') {
            my $reseller_id = $c->user->reseller_id;
            my $tz_row = $c->model('DB')->resultset('reseller_timezone')->find({reseller_id => $reseller_id});
            _set_session_tz_from_row($c, $tz_row, 'admin', $reseller_id);
        } elsif($c->user->roles eq 'ccare') {
            my $reseller_id = $c->user->reseller_id;
            my $tz_row = $c->model('DB')->resultset('reseller_timezone')->find({reseller_id => $reseller_id});
            _set_session_tz_from_row($c, $tz_row, 'reseller', $reseller_id);
        } elsif($c->user->roles eq 'lintercept') {
            my $reseller_id = $c->user->reseller_id;
            my $tz_row = $c->model('DB')->resultset('reseller_timezone')->find({reseller_id => $reseller_id});
            _set_session_tz_from_row($c, $tz_row, 'reseller', $reseller_id);
        } else {
            # this should not happen
        }
        $NGCP::Schema::CURRENT_USER_TZ = $c->session->{user_tz};
    } else {
        $NGCP::Schema::CURRENT_USER_TZ = undef;
    }

    ###################################################

    if (
        __PACKAGE__ eq $c->controller->catalyst_component_name
        or 'NGCP::Panel::Controller::Login' eq $c->controller->catalyst_component_name
        or $c->req->uri->path =~ m|^/device/autoprov/.+|
        or $c->req->uri->path =~ m|^/pbx/directory/.+|
        or $c->req->uri->path =~ m|^/recoverwebpassword/?$|
        or $c->req->uri->path =~ m|^/resetwebpassword/?$|
        or $c->req->uri->path =~ m|^/resetpassword/?$|
        or $c->req->uri->path =~ m|^/api/passwordreset/?$|
        or $c->req->uri->path =~ m|^/api/passwordrecovery/?$|
        or $c->req->uri->path =~ m|^/internalsms/receive/?$|
        or $c->req->uri->path =~ m|^/soap/intercept(\.wsdl)?/?$|i
    ) {
        $c->log->debug("Root::auto skip authn, grant access to " . $c->request->path);
        return 1;
    }

    if(index($c->controller->catalyst_component_name, 'NGCP::Panel::Controller::API') == 0) {
        $c->log->debug("Root::auto unauthenticated API request");
        my $ssl_dn = $c->request->env->{SSL_CLIENT_M_DN} // "";
        my $ssl_sn = hex ($c->request->env->{SSL_CLIENT_M_SERIAL} // 0);
        my $ngcp_api_realm = $c->request->env->{NGCP_API_REALM} // "";
        if($ssl_sn) {
            $c->log->debug("Root::auto API request with client auth sn '$ssl_sn'");
            unless($ssl_dn =~ /^\/?CN=Sipwise NGCP API client certificate$/) {
                $c->log->error("Root::auto API request with invalid client DN '" . $ssl_dn . "'");
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
            unless ($c->user_exists) {
                $c->log->warn("invalid api login from '".$c->qs($c->req->address)."'");
                $c->detach(qw(API::Root invalid_user), [$ssl_sn]) unless $c->user_exists;
            } else {
                $c->log->debug("admin '".$c->user->login."' authenticated via api_admin_cert");
            }
            if($c->user->read_only && $c->req->method eq "POST" &&
                    $c->req->uri->path =~ m|^/api/admincerts/$|) {
                $c->log->info("let read-only user '".$c->user->login."' generate admin cert for itself");
            } elsif($c->user->read_only && !($c->req->method =~ /^(GET|HEAD|OPTIONS)$/)) {
                $c->log->error("invalid method '".$c->req->method."' for read-only user '".$c->user->login."', rejecting");
                $c->user->logout;
                $c->log->error("body data: " . $c->qs($c->req->body_data));
                $c->response->status(403);
                $c->res->body(JSON::to_json({
                    message => "Invalid HTTP method for read-only user",
                    code => 403,
                }));
                return;
            }
            $self->api_apply_fake_time($c);
            return $self->check_user_access($c);
        } elsif ($c->req->headers->header("NGCP-UserAgent") &&
                 $c->req->headers->header("NGCP-UserAgent") eq "NGCP::API::Client") {
            $c->log->debug("Root::auto API request with system auth");
            my $realm = "api_admin_system";
            my $res = $c->authenticate({}, $realm);

            unless ($c->user_exists) {
                $c->log->debug("invalid api admin system login");
                $c->log->warn("invalid api system login from '".$c->qs($c->req->address)."'");
            }

            $self->api_apply_fake_time($c);
            return $self->check_user_access($c);
        } elsif ($c->req->headers->header("Authorization") &&
                 $c->req->headers->header("Authorization") =~ m/^Bearer /) {
            my $ngcp_api_realm = $c->request->env->{NGCP_API_REALM} // "";
            if ($ngcp_api_realm eq 'subscriber') {
                $c->log->debug("Root::auto API request with JWT");
                my $realm = "api_subscriber_jwt";
                my $res = $c->authenticate({}, $realm);

                unless ($c->user_exists) {
                    $c->log->debug("Invalid api subscriber JWT login");
                }
            } else {
                $c->log->debug("Root::auto API request with admin JWT");
                my $realm = "api_admin_jwt";
                my $res = $c->authenticate({}, $realm);

                unless ($c->user_exists) {
                    $c->log->debug("Invalid api admin JWT login");
                }
            }

            $self->api_apply_fake_time($c);
            return $self->check_user_access($c);
        } elsif ($ngcp_api_realm eq "subscriber") {
            $c->log->debug("Root::auto API subscriber request with http auth");
            my $realm = "api_subscriber_http";

            if ($c->req->uri->path =~ m|^/api/platforminfo/?$| &&
                !$c->req->headers->authorization_basic) {
                    $c->detach(qw(API::Root platforminfo));
            }

            my ($username,$password) = $c->req->headers->authorization_basic;
            my ($u,$d) = split(/\@/,$username);
            if ($d) {
                $c->req->headers->authorization_basic($u,$password);
            }
            my $res = NGCP::Panel::Utils::Auth::perform_subscriber_auth($c, $u, $d, $password);

            if($res && $c->user_exists) {
                $d //= $c->req->uri->host;
                $c->log->debug("checking '".$c->user->domain->domain."' against '$d'");
                if ($c->user->domain->domain ne $d) {
                    $c->user->logout;
                    $c->log->debug("invalid api subscriber http login by '$username' (domain check failed)");
                    $c->log->warn("invalid api http login from '".$c->qs($c->req->address)."' by '" . $c->qs($username) ."'");
                    my $r = $c->get_auth_realm($realm);
                    $r->credential->authorization_required_response($c, $r);
                    return;
                }
                $c->log->debug("subscriber '$username' authenticated via api_subscriber_http");
            } else {
                $c->user->logout if($c->user);
                $c->log->debug("invalid api subscriber http login");
                $c->log->warn("invalid api http login from '".$c->qs($c->req->address)."' by '" . $c->qs($username) ."'");
                my $r = $c->get_auth_realm($realm);
                $r->credential->authorization_required_response($c, $r);
                return;
            }
            $self->api_apply_fake_time($c);
            return $self->check_user_access($c);
        } else {
            $c->log->debug("Root::auto API admin request with http auth");
            my ($user, $pass) = $c->req->headers->authorization_basic;
            #$c->log->debug("user: " . $user . " pass: " . $pass);
            my $res = NGCP::Panel::Utils::Auth::perform_auth($c, $user, $pass, "api_admin" , "api_admin_bcrypt");
            if($res and $c->user_exists and $c->user->is_active)  {
                $c->log->debug("admin '".$c->user->login."' authenticated via api_admin_http");
            } else {
                my $realm = 'api_admin_http';

                if ($c->req->uri->path =~ m|^/api/platforminfo/?$| &&
                    !$c->req->headers->authorization_basic) {
                        $c->detach(qw(API::Root platforminfo));
                }

                $c->user->logout if($c->user);
                $c->log->debug("invalid api admin http login");
                $c->log->warn("invalid api http login from '".$c->req->address."' by '$user'");
                my $r = $c->get_auth_realm($realm);
                $r->credential->authorization_required_response($c, $r);
                return;
            }
            if($c->user->read_only && $c->req->method eq "POST" &&
                    $c->req->uri->path =~ m|^/api/admincerts/$|) {
                $c->log->info("let read-only user '".$c->user->login."' generate admin cert for itself");
                return 1;
            } elsif($c->user->read_only && !($c->req->method =~ /^(GET|HEAD|OPTIONS)$/)) {
                $c->log->error("invalid method '".$c->req->method."' for read-only user '".$c->user->login."', rejecting");
                $c->user->logout;
                $c->log->error("body data: " . $c->req->body_data);
                $c->response->status(403);
                $c->res->body(JSON::to_json({
                    message => "Invalid HTTP method for read-only user",
                    code => 403,
                }));
                return;
            }
            $self->api_apply_fake_time($c);
            return $self->check_user_access($c);
        }
    } elsif (!$c->user_exists &&
            $c->req->headers->header("Authorization") &&
            $c->req->headers->header("Authorization") =~ m/^Bearer /) {

        $c->log->debug("Root::auto UI request with admin JWT");
        my $realm = "admin_jwt";
        my $res = $c->authenticate({}, $realm);

        unless ($c->user_exists) {
            $c->log->debug("invalid UI admin JWT login");
        }

        $self->api_apply_fake_time($c);
        return $self->check_user_access($c);
    } elsif (!$c->user_exists) {

        # don't redirect to login page for ajax uris
        if($c->request->path =~ /\/ajax$/) {
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
        $c->log->debug("Root::auto do login, target='$target'");
        $c->session(target => $target);
        $c->response->redirect($c->uri_for('/login'));
        return;
    }

    $c->log->debug("Root::auto grant access for authenticated user");

    if (exists $c->config->{external_documentation}{link} && 'ARRAY' ne ref $c->config->{external_documentation}{link}) {
        $c->config->{external_documentation}{link} = [$c->config->{external_documentation}{link}];
    }

    # load top menu widgets
    my $topmenu_templates = [];
    $topmenu_templates = ['widgets/'.$c->user->roles.'_topmenu_settings.tt'];
    $c->stash(topmenu => $topmenu_templates);

    $self->include_framed($c);

    $c->session->{created_objects} = {} unless(defined $c->session->{created_objects});

    return $self->check_user_access($c);
}

sub include_framed {
    my ($self, $c) = @_;

    $c->session->{framed} = 1 if ($c->req->params->{framed} && $c->req->params->{framed} == 1);
    $c->session->{framed} = 0 if not defined $c->req->headers->header("referer");
    $c->session->{framed} = 0 if (defined $c->req->params->{framed} && $c->req->params->{framed} == 0);
    $c->session->{framed} = 0 if (defined $c->req->headers->header("sec-fetch-dest") && $c->req->headers->header("sec-fetch-dest") eq "document");
    $c->session->{framed} = 1 if (defined $c->req->headers->header("sec-fetch-dest") && $c->req->headers->header("sec-fetch-dest") eq "iframe");
    $c->stash(framed => $c->session->{framed}) if ($c->session->{framed} && $c->session->{framed} == 1);

    return;
}

sub root_index :Path :Args(0) {
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

# any path that is not matched by anything else (e.g. /foo/bar)
sub root_default :Path {
    my ( $self, $c ) = @_;

    $self->include_framed($c);

    $c->log->debug("Root::root_default 404 Not found. Requested unknown resource.");
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
        $c->log->error("fatal error, id=$incident_id, timestamp=$incident_timestamp, error=".join(q(), map { $c->qs($_); } @{ $c->error }));
        $c->clear_errors;
        $c->stash(
            exception_incident => $incident_id,
            exception_timestamp => $incident_timestamp,
            template => 'error_page.tt'
        );
        $c->log->debug("Root::end 500 Internal error");
        $c->response->status(500);
        $c->detach($c->view);
    }
    $c->stash->{_request_done} = Time::HiRes::time;
    my $total = $c->stash->{_request_done} - $c->stash->{_request_start};
    $c->log->debug("Root::end Finished in $total seconds" );
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
    $c->log->debug("Root::error_page 404 Not found");
}

sub denied_page :Private {
    my ($self,$c) = @_;

    $c->log->error('Access denied to path ' . $c->request->path );
    if($c->request->path =~ /^api\/.+/) {
        $c->response->content_type('application/json');
        $c->response->body(JSON::to_json({ code => 403, message => 'Forbidden' })."\n");
    } else {
        $c->stash(template => 'denied_page.tt');
    }
    $c->response->status(403);
    $c->log->debug("Root::denied_page 403 Access denied");
}

sub check_user_access {
    my ($self, $c) = @_;

    my $path = $c->req->uri->path;

    if ($path =~ /^\/(login|logout|login_jwt)$/) {
        return 1;
    }

    # deny access to inactive users
    if ($c->user_exists && !$c->user->uuid && !$c->user->is_active) {
        $c->detach('/denied_page');
        return;
    }

    # deny access to read-only users
    if ($c->user_exists && $c->user->read_only &&
        ($path =~ /create/ ||
         $path =~ /edit/   ||
         $path =~ /delete/ ||
         $c->req->method =~ /^(POST|PUT|PATCH|DELETE)$/)) {
        $c->detach('/denied_page');
        return;
    }

    return 1;
}

sub emptyajax :Chained('/') :PathPart('emptyajax') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        aaData => [],
        iTotalDisplayRecords => 0,
        iTotalRecords => 0,
        iTotalRecordCountClipped        => \0,
        iTotalDisplayRecordCountClipped => \0,
        sEcho => $c->request->params->{sEcho} // 1,
    );
    $c->detach( $c->view("JSON") );
}

sub login_jwt :Chained('/') :PathPart('login_jwt') :Args(0) :Method('POST') {
    my ($self, $c) = @_;

    use JSON qw/encode_json decode_json/;
    use Crypt::JWT qw/encode_jwt/;

    my $auth_token = $c->req->body_data->{token} // '';
    my $user = $c->req->body_data->{username} // '';
    my $pass = $c->req->body_data->{password} // '';
    my $ngcp_realm = $c->request->env->{NGCP_REALM} // 'admin';

    my $key = $ngcp_realm eq 'admin'
                ? $c->config->{'Plugin::Authentication'}{api_admin_jwt}{credential}{jwt_key}
                : $c->config->{'Plugin::Authentication'}{api_subscriber_jwt}{credential}{jwt_key};
    my $relative_exp = $ngcp_realm eq 'admin'
                ? $c->config->{'Plugin::Authentication'}{api_admin_jwt}{credential}{relative_exp}
                : $c->config->{'Plugin::Authentication'}{api_subscriber_jwt}{credential}{relative_exp};
    my $alg = $ngcp_realm eq 'admin'
                ? $c->config->{'Plugin::Authentication'}{api_admin_jwt}{credential}{alg}
                : $c->config->{'Plugin::Authentication'}{api_subscriber_jwt}{credential}{alg};

    $c->response->content_type('application/json');

    unless ($key) {
        $c->response->status(HTTP_INTERNAL_SERVER_ERROR);
        $c->response->body(encode_json({ code => HTTP_INTERNAL_SERVER_ERROR,
            message => "No JWT key has been configured" })."\n");
        $c->log->error("No JWT key has been configured");
        return;
    }

    unless ($ngcp_realm eq 'admin' || $ngcp_realm eq 'subscriber') {
        $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
        $c->response->body(encode_json({ code => HTTP_UNPROCESSABLE_ENTITY,
            message => "Invalid realm" })."\n");
        $c->log->error("Invalid realm");
        return;
    }

    my $auth_user;
    if ($auth_token) {
        my $redis = NGCP::Panel::Utils::Redis::get_redis_connection($c, {database => $c->config->{'Plugin::Session'}->{redis_db}});

        unless ($redis) {
            $c->response->status(HTTP_INTERNAL_SERVER_ERROR);
            $c->response->body(encode_json({ code => HTTP_INTERNAL_SERVER_ERROR,
            message => "Internal Server Error" })."\n");
            $c->log->error("Could not connect to Redis");
            return;
        }

        my $type = $redis->hget("auth_token:$auth_token", "type");
        my $role = $redis->hget("auth_token:$auth_token", "role");
        my $user_id = $redis->hget("auth_token:$auth_token", "user_id");

        unless ($type && $role && $user_id) {
            $c->response->status(HTTP_FORBIDDEN);
            $c->response->body(encode_json({ code => HTTP_FORBIDDEN,
                                             message => "Forbidden!" })."\n");
            $c->log->error("Unknown auth_token");
            return;
        }

        $redis->del("auth_token:$auth_token") if $type eq 'onetime';

        if ($ngcp_realm eq 'admin') {
            unless (grep {$role eq $_} qw/admin reseller ccare ccareadmin/) {
                $c->response->status(HTTP_FORBIDDEN);
                $c->response->body(encode_json({ code => HTTP_FORBIDDEN,
                                                 message => "Forbidden!" })."\n");
                $c->log->error("Wrong auth_token role");
                return;
            }

            my $authrs = $c->model('DB')->resultset('admins')->search({
                id => $user_id,
                is_active => 1,
            });

            $auth_user = $authrs->first if ($authrs->first);
        } else {
            unless (grep {$role eq $_} qw/subscriber subscriberadmin/) {
                $c->response->status(HTTP_FORBIDDEN);
                $c->response->body(encode_json({ code => HTTP_FORBIDDEN,
                message => "Forbidden!" })."\n");
                $c->log->error("Wrong auth_token role");
                return;
            }

            my $authrs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                'me.id' => $user_id,
                'voip_subscriber.status' => 'active',
                'contract.status' => 'active',
            }, {
                join => ['contract', 'voip_subscriber'],
            });

            $auth_user = $authrs->first if ($authrs->first);
        }
    } else {
        unless ($user && $pass) {
            $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
            $c->response->body(encode_json({ code => HTTP_UNPROCESSABLE_ENTITY,
                message => "No username or password given" })."\n");
            $c->log->error("No username or password given");
            return;
        }

        unless (NGCP::Panel::Utils::Auth::check_password($pass)) {
            $c->response->status(HTTP_UNPROCESSABLE_ENTITY);
            $c->response->body(encode_json({ code => HTTP_UNPROCESSABLE_ENTITY,
                message => "'password' contains invalid characters" })."\n");
            $c->log->error("'password' contains invalid characters");
            return;
        }

        my ($u, $d, $t) = split(/\@/, $user, 3);

        if(defined $t) {
            # in case username is an email address
            $u = $u . '@' . $d;
            $d = $t;
        }

        unless(defined $d) {
            $d = $c->req->uri->host;
        }

        if ($ngcp_realm eq 'admin') {
            my $authrs = $c->model('DB')->resultset('admins')->search({
                login => $user,
                is_active => 1,
            });

            my $usr_salted_pass;
            $auth_user = $authrs->first;

            if ($auth_user && $auth_user->id) {
                $usr_salted_pass = NGCP::Panel::Utils::Auth::get_usr_salted_pass($auth_user->saltedpass, $pass);
            }

            unless ($usr_salted_pass && $usr_salted_pass eq $auth_user->saltedpass) {
                $c->response->status(HTTP_FORBIDDEN);
                $c->response->body(encode_json({ code => HTTP_FORBIDDEN,
                    message => "User not found" })."\n");
                $c->log->error("User not found");
                return;
            }
        } else {
            my $authrs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                webusername => $u,
                'voip_subscriber.status' => 'active',
                'domain.domain' => $d,
                'contract.status' => 'active',
            }, {
                join => ['domain', 'contract', 'voip_subscriber'],
            });

            if ($authrs->first) {
                my $password = $authrs->first->webpassword;
                if (defined $password and length($password) > 40) {
                    my @splitted_pass = split /\$/, $password;
                    if (scalar @splitted_pass == 3) {
                        #password is bcrypted with lower cost
                        my ($cost, $db_b64salt, $db_b64hash) = @splitted_pass;
                        my $salt = de_base64($db_b64salt);
                        my $usr_b64hash = en_base64(bcrypt_hash({
                            key_nul => 1,
                            cost => $cost,
                            salt => $salt,
                        }, $pass));
                        if ($db_b64hash eq $usr_b64hash) {
                            #upgrade password to bigger cost
                            $salt = rand_bits(128);
                            my $b64salt = en_base64($salt);
                            my $b64hash = en_base64(bcrypt_hash({
                                key_nul => 1,
                                cost => NGCP::Panel::Utils::Auth::get_bcrypt_cost(),
                                salt => $salt,
                            }, $pass));
                            $authrs->first->update({webpassword => $b64salt . '$' . $b64hash});
                            $auth_user = $authrs->first;
                        }
                    }
                    elsif (scalar @splitted_pass == 2) {
                        #password is bcrypted with proper cost
                        my ($db_b64salt, $db_b64hash) = @splitted_pass;
                        my $salt = de_base64($db_b64salt);
                        my $usr_b64hash = en_base64(bcrypt_hash({
                            key_nul => 1,
                            cost => NGCP::Panel::Utils::Auth::get_bcrypt_cost(),
                            salt => $salt,
                        }, $pass));
                        $auth_user = $authrs->search({webpassword => $db_b64salt . '$' . $usr_b64hash})->first;
                    }
                } else {
                    $auth_user = $authrs->search({webpassword => $pass})->first;
                }
            }
        }
    }

    my $result = {};

    if ($ngcp_realm eq 'admin') {
        if ($auth_user) {
            my $jwt_data = {
                id => $auth_user->id,
                username => $auth_user->login,
            };
            $result->{jwt} = encode_jwt(
                payload => $jwt_data,
                key => $key,
                alg => $alg,
                $relative_exp ? (relative_exp => $relative_exp) : (),
                extra_headers => { typ => 'JWT' },
            );
            $result->{id} = int($auth_user->id // 0);
        } else {
            $c->response->status(HTTP_FORBIDDEN);
            $c->response->body(encode_json({ code => HTTP_FORBIDDEN,
                message => "User not found" })."\n");
            $c->log->error("User not found");
            return;
        }
    } else {
        if ($auth_user && $auth_user->voip_subscriber) {
            my $jwt_data = {
                subscriber_uuid => $auth_user->uuid,
                username => $auth_user->webusername,
            };
            $result->{jwt} = encode_jwt(
                payload => $jwt_data,
                key => $key,
                alg => $alg,
                $relative_exp ? (relative_exp => $relative_exp) : (),
                extra_headers => { typ => 'JWT' },
            );
            $result->{subscriber_id} = int($auth_user->voip_subscriber->id // 0);
        } else {
            $c->response->status(HTTP_FORBIDDEN);
            $c->response->body(encode_json({ code => HTTP_FORBIDDEN,
                message => "User not found" })."\n");
            $c->log->error("User not found");
            return;
        }
    }

    $c->res->body(encode_json($result));
    $c->res->code(HTTP_OK);  # 200

    return;
}

sub login_to_v2 :Chained('/') :PathPart('login_to_v2') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page') unless ($c->user_exists);

    use JSON qw/encode_json decode_json/;
    use Crypt::JWT qw/encode_jwt/;
    use Redis;

    my $key = $c->config->{'Plugin::Authentication'}{api_admin_jwt}{credential}{jwt_key};
    my $relative_exp = $c->config->{'Plugin::Authentication'}{api_admin_jwt}{credential}{relative_exp};
    my $alg = $c->config->{'Plugin::Authentication'}{api_admin_jwt}{credential}{alg};

    unless ($key) {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            desc => $c->loc('No JWT key has been configured.'),
        );
    }

    my $jwt_data = {
        id => $c->user->id,
        username => $c->user->login,
    };
    my $token = encode_jwt(
        payload => $jwt_data,
        key => $key,
        alg => $alg,
        $relative_exp ? (relative_exp => $relative_exp) : (),
    );

    my $redis = Redis->new(
        server => $c->config->{redis}->{central_url},
        reconnect => 10, every => 500000, # 500ms
        cnx_timeout => 3,
    );
    unless ($redis) {
        $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
        return;
    }
    $redis->select($c->config->{'Plugin::Session'}->{redis_db});
    $redis->set("jwt:$token", '');
    $redis->expire("jwt:$token", 300);

    $c->res->redirect($c->req->base.'v2/#/'.$c->req->params->{page});
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

sub _set_session_tz_from_row {
    my ($c, $tz_row, $role, $identifier) = @_;

    my $tz_name = $tz_row ? $tz_row->name : undef;
    $tz_name =~ s/^localtime$/local/ if $tz_name;
    eval { $c->session->{user_tz} = DateTime::TimeZone->new( name => $tz_name ); };
    if ($@) {
        $c->log->warn("could not set timezone. error in creation probably caused by invalid timezone name. role $role ($identifier) to $tz_name");
    } else {
        $c->session->{user_tz_name} = $tz_name;
        $c->log->debug("timezone set for $role ($identifier) to $tz_name");
    }
}

sub _handle_api_lang {
    my $self = shift;
    my ($c) = @_;

    my $lang = 'i-default';
    if (defined $c->request->params->{lang} && $c->request->params->{lang} =~ /^\w+$/) {
        $lang = $self->_resolve_lang($c, $c->request->params->{lang});
    }

    $c->languages([$lang]);
}

sub _handle_ui_lang {
    my $self = shift;
    my ($c) = @_;

    my $lang;
    if (defined $c->request->params->{lang} && $c->request->params->{lang} =~ /^\w+$/) {
        $lang = $self->_resolve_lang($c, $c->request->params->{lang});
        if ($c->request->params->{lang_save}) {
            $c->response->cookies->{ngcp_panel_lang} = {value => $lang, expires =>  '+3M',};
        }
    } else {
        $lang = defined $c->req->cookie('ngcp_panel_lang') ?
                $c->req->cookie('ngcp_panel_lang')->value :
                'i-default';
    }

    $c->languages([$lang]);
}

sub _resolve_lang {
    my $self = shift;
    my ($c, $lang) = @_;

    if (exists $c->installed_languages->{$lang}) {
        return $lang;
    }

    if (defined $c->config->{appearance}{force_language}) {
        return $c->config->{appearance}{force_language};
    }

    return 'i-default';
}


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
