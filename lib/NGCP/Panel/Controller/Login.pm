package NGCP::Panel::Controller::Login;

use warnings;
use strict;

use parent 'Catalyst::Controller';
use TryCatch;
use UUID;
use MIME::Base64;

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Auth;
use NGCP::Panel::Utils::Form;
use NGCP::Panel::Utils::Subscriber;

sub login_index :Path Form {
    my ( $self, $c, $realm ) = @_;

    my $posted = ($c->req->method eq 'POST');
    my $form;

    if ($c->request->params->{otp}) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::LoginOtp", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Login", $c);
    }

    if (not $realm 
        or $realm ne 'admin') {
        $realm = 'subscriber';
    }
    
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => { username => $c->stash->{username} },
    );

    if($posted && $form->validated) {
        $c->log->debug("login form validated");
        my $user = $form->field('username')->value;
        my $pass = $form->field('password')->value;
        my $otp;
        if ($form->field('otp')) {
            $otp = $form->field('otp')->value;
            $c->log->debug("Login::index user=$user, pass=****, otp=$otp, realm=$realm");
        } else {
            $c->log->debug("Login::index user=$user, pass=****, realm=$realm");
        }
        my $res;
        my ($u, $d, $t);
        if($realm eq 'admin') {
            $res = NGCP::Panel::Utils::Auth::perform_auth(
                c => $c,
                user => $user,
                pass => $pass,
                otp => $otp,
                realm => 'admin',
                bcrypt_realm => 'admin_bcrypt',
            );
        } elsif($realm eq 'subscriber') {
            ($u, $d, $t) = split /\@/, $user;
            if(defined $t) {
                # in case username is an email address
                $u = $u . '@' . $d;
                $d = $t;
            }
            unless(defined $d) {
                $d = $c->req->uri->host;
            }
            $res = NGCP::Panel::Utils::Auth::perform_subscriber_auth(
                c => $c,
                user => $u,
                domain => $d,
                pass => $pass,
                otp => $otp,
            );
        }

        if(defined $res && $res == -3) {
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::LoginOtp", $c);
            $form->field('username')->value($user);
            $form->field('password')->value($pass);            
            $form->field('otp')->value(undef);
            $form->add_form_error($c->loc('Invalid one-time code')) if $otp;
            if($realm eq 'admin') {
                my $dbadmin = $c->model('DB')->resultset('admins')->search({
                    login => $user,
                })->first;
                $c->stash(show_otp_registration_info => $dbadmin->show_otp_registration_info);
                if ($dbadmin->show_otp_registration_info) {
                    $c->stash(
                        otp_secret_qr_base64 => encode_base64(${NGCP::Panel::Utils::Auth::generate_otp_qr($c,$dbadmin)}),
                    );
                }
            } elsif($realm eq 'subscriber') {
                my $sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                    webusername => $u,
                    'voip_subscriber.status' => 'active',
                    ($c->config->{features}->{multidomain} ? ('domain.domain' => $d) : ()),
                    'contract.status' => 'active',
                }, {
                    join => ['domain', 'contract', 'voip_subscriber'],
                })->first;
                my $show_otp_registration_info = NGCP::Panel::Utils::Auth::get_subscriber_show_otp_registration_info($c,$sub);
                $c->stash(show_otp_registration_info => $show_otp_registration_info);
                if ($show_otp_registration_info) {
                    $c->stash(
                        otp_secret_qr_base64 => encode_base64(${NGCP::Panel::Utils::Auth::generate_otp_qr($c,$sub)}),
                    );
                }
            }
        } elsif($res && $res == -2) {
            $c->log->warn("invalid http login from '".$c->qs($c->req->address)."'");
            $c->log->debug("Login::index auth failed");
            $form->add_form_error($c->loc('User banned')) 
        } elsif($res) {
            # auth ok
            if ($realm eq 'admin') {
                use Crypt::JWT qw/encode_jwt/;

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

                $c->session->{aui_adminId} = $c->user->id;
                $c->session->{aui_jwt} = $token;
            }

            $c->session->{user_tz} = undef;  # reset to reload from db
            $c->session->{user_tz_name} = undef;  # reset to reload from db
            my $target = $c->session->{'target'} || '/dashboard';
            delete $c->session->{target};
            $target =~ s!^https?://[^/]+/!/!;
            $c->log->debug("Login::index auth ok, redirecting to $target");
            $c->response->redirect($target);
            return;
        } else {
            $c->log->warn("invalid http login from '".$c->qs($c->req->address)."'");
            $c->log->debug("Login::index auth failed");
            $form->add_form_error($c->loc('Invalid username/password')) 
            
        }
    } else {
        # initial get
    }

    if ($form->has_errors) {
        my $request_ip = $c->request->address;
        $c->log->error("NGCP Panel Login failed realm=$realm ip=" . $c->qs($request_ip));
    }

    $c->stash(form => $form);
    $c->stash(realm => $realm);
    $c->stash(template => 'login/login.tt');
}

sub reset_password :Chained('/') :PathPart('resetpassword') :Args(0) {
    my ($self, $c) = @_;

    my $posted = $c->req->method eq "POST";
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::ResetPassword", $c);
    my $params = {};
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $username = $form->params->{username};
                my $admin = $schema->resultset('admins')->search({
                    login => $username,
                })->first;

                # don't inform about unknown users
                if($admin) {
                    if (!$admin->email) {
                        NGCP::Panel::Utils::Message::error(
                            c    => $c,
                            desc => $c->loc('Admin does not have an email set'),
                        );
                    }
                    elsif ($admin->can_reset_password) {
                        my $result = NGCP::Panel::Utils::Auth::initiate_password_reset($c, $admin);
                        if (!$result->{success}) {
                            NGCP::Panel::Utils::Message::error(
                                c    => $c,
                                desc => $c->loc($result->{error}),
                            );
                        }
                        else {
                            NGCP::Panel::Utils::Message::info(
                                c    => $c,
                                desc => $c->loc('Successfully reset password, please check your email'),
                            );
                        }
                    }
                    else {
                        NGCP::Panel::Utils::Message::error(
                            c    => $c,
                            desc => $c->loc('This user is not allowed to reset password'),
                        );
                    }
                }
            });
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to reset password'),
            );
        }
        $c->res->redirect($c->uri_for('/login/admin'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
        template => 'administrator/reset_password.tt',
        close_target => $c->uri_for('/login/admin'),
    );
}

sub recover_password :Chained('/') :PathPart('recoverpassword') :Args(0) {
    my ($self, $c) = @_;

    $c->user->logout if($c->user);

    my $posted = $c->req->method eq "POST";
    my ($uuid_bin, $uuid_string);
    $uuid_string = $c->req->params->{token} // '';

    unless($uuid_string && UUID::parse($uuid_string, $uuid_bin) != -1) {
        $c->log->warn("invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
        $c->detach('/denied_page')
    }

    my $redis = $c->redis_get_connection({database => $c->config->{'Plugin::Session'}->{redis_db}});
    unless ($redis) {
        $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
        return;
    }
    my $ip = $redis->hget("password_reset:admin::$uuid_string", "ip");
    if ($ip && $ip ne $c->req->address) {
        $c->log->warn("invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
        $c->detach('/denied_page');
    }
    my $admin = $redis->hget("password_reset:admin::$uuid_string", "user");
    my $administrator;
    if ($admin) {
        $administrator = $c->model('DB')->resultset('admins')->search({login => $admin})->first;
        unless ($administrator) {
            $c->log->warn("invalid password recovery attempt for token '$uuid_string' from '".$c->qs($c->req->address)."'");
            $c->detach('/denied_page');
        }
    }
    else {
        NGCP::Panel::Utils::Message::error(
            c    => $c,
            desc => $c->loc('Invalid token'),
        );
        $c->res->redirect($c->uri_for('/login/admin'));
    }

    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::RecoverPassword", $c);
    my $params = {
        token => $uuid_string,
    };
    $form->process(
        posted => $posted,
        params => $c->req->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
                $administrator->update({
                    saltedpass => NGCP::Panel::Utils::Auth::generate_salted_hash($form->params->{password}),
                });
                $redis->del("password_reset:admin::$uuid_string");
                $redis->del("password_reset:admin::$admin");
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                type  => 'internal',
                desc  => $c->loc('Failed to recover password'),
            );
            $c->detach('/denied_page');
        }

        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { username => $administrator->login },
            desc => $c->loc('Password successfully recovered, please re-login.'),
        );
        $c->flash(username => $administrator->login);
        $c->res->redirect($c->uri_for('/login/admin'));
        return;

    }

    $c->stash(
        form => $form,
        edit_flag => 1,
        template => 'administrator/reset_password.tt',
        close_target => $c->uri_for('/login/admin'),
    );
}

sub change_password :Chained('/') :PathPart('changepassword') Args(0) {
    my ($self, $c) = @_;

    my $realm = $c->req->env->{NGCP_REALM} // 'admin';

    $c->user->logout if $c->user;

    my $posted = ($c->req->method eq 'POST');
    my $form;

    if ($c->request->params->{otp}) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::PasswordChangeOtp", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::PasswordChange", $c);
    }

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => { username => $c->stash->{username} },
    );

    if($posted && $form->validated) {
        $c->log->debug("login form validated");
        my $user = $form->field('username')->value;
        my $pass = $form->field('password')->value;
        my $otp;
        my $new_pass = $form->field('new_password')->value;
        my $new_pass2 = $form->field('new_password2')->value;
        if ($form->field('otp')) {
            $otp = $form->field('otp')->value;
            $c->log->debug("Password change user=$user, pass=****, otp=$otp, realm=$realm");
        } else {
            $c->log->debug("Password change user=$user, pass=****, realm=$realm");
        }
        my $res;
        my ($u, $d, $t);
        if($realm eq 'admin') {
            $res = NGCP::Panel::Utils::Auth::perform_auth(
                c => $c,
                user => $user,
                pass => $pass,
                otp => $otp,
                realm => 'admin',
                bcrypt_realm => 'admin_bcrypt',
            );
        } elsif($realm eq 'subscriber') {
            ($u, $d, $t) = split /\@/, $user;
            if(defined $t) {
                # in case username is an email address
                $u = $u . '@' . $d;
                $d = $t;
            }
            unless(defined $d) {
                $d = $c->req->uri->host;
            }
            $res = NGCP::Panel::Utils::Auth::perform_subscriber_auth(
                c => $c,
                user => $u,
                domain => $d,
                pass => $pass,
                otp => $otp,
            );
        }

        if(defined $res && $res == -3) {
            $form = NGCP::Panel::Form::get("NGCP::Panel::Form::PasswordChangeOtp", $c);
            $form->field('username')->value($user);
            $form->field('password')->value($pass);
            $form->field('otp')->value(undef);
            $form->field('new_password')->value($new_pass);
            $form->field('new_password')->value($new_pass2);
            $form->add_form_error($c->loc('Invalid one-time code')) if $otp;
            if($realm eq 'admin') {
                my $dbadmin = $c->model('DB')->resultset('admins')->search({
                    login => $user,
                })->first;
                $c->stash(show_otp_registration_info => $dbadmin->show_otp_registration_info);
                if ($dbadmin->show_otp_registration_info) {
                    $c->stash(
                        otp_secret_qr_base64 => encode_base64(${NGCP::Panel::Utils::Auth::generate_otp_qr($c,$dbadmin)}),
                    );
                }
            } elsif($realm eq 'subscriber') {
                my $sub = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                    webusername => $u,
                    'voip_subscriber.status' => 'active',
                    ($c->config->{features}->{multidomain} ? ('domain.domain' => $d) : ()),
                    'contract.status' => 'active',
                }, {
                    join => ['domain', 'contract', 'voip_subscriber'],
                })->first;
                my $show_otp_registration_info = NGCP::Panel::Utils::Auth::get_subscriber_show_otp_registration_info($c,$sub);
                $c->stash(show_otp_registration_info => $show_otp_registration_info);
                if ($show_otp_registration_info) {
                    $c->stash(
                        otp_secret_qr_base64 => encode_base64(${NGCP::Panel::Utils::Auth::generate_otp_qr($c,$sub)}),
                    );
                }
            }
        } elsif($res && $res == -2) {
            $c->log->warn("invalid http login from '".$c->qs($c->req->address)."'");
            $c->log->debug("Login::index auth failed");
            $form->add_form_error($c->loc('User banned')) 
        } elsif($res) {
            # auth ok

            if ($pass eq $new_pass) {
                $form->field('new_password')->add_error($c->loc('Password must not be equal to the old password'));
            } elsif ($new_pass ne $new_pass2) {
                $form->field('new_password2')->add_error($c->loc('New password fields do not match'));
            } else {
                NGCP::Panel::Utils::Form::validate_password(
                    c => $c, field => $form->field('new_password'), admin => $realm eq 'admin', password_change => 1
                );
            }

            if (!$form->has_errors) {
                if ($realm eq 'admin') {
                    use Crypt::JWT qw/encode_jwt/;

                    $c->user->update({
                        saltedpass => NGCP::Panel::Utils::Auth::generate_salted_hash($new_pass)
                    });
                    NGCP::Panel::Utils::Admin::insert_password_journal(
                        $c, $c->user, $new_pass
                    );

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

                    $c->session->{aui_adminId} = $c->user->id;
                    $c->session->{aui_jwt} = $token;
                } else {
                    $c->user->provisioning_voip_subscriber->update({
                        webpassword =>
                            $NGCP::Panel::Utils::Auth::ENCRYPT_SUBSCRIBER_WEBPASSWORDS
                                ? NGCP::Panel::Utils::Auth::generate_salted_hash($new_pass)
                                : $new_pass
                    });
                    NGCP::Panel::Utils::Subscriber::insert_webpassword_journal(
                        $c, $c->user->provisioning_voip_subscriber, $new_pass
                    );

                }
                $c->log->debug("Password successfully changed for user=$user, realm=$realm");
                $c->session->{user_tz} = undef;  # reset to reload from db
                $c->session->{user_tz_name} = undef;  # reset to reload from db
                my $target = $c->session->{'target'} || '/dashboard';
                delete $c->session->{target};
                $target =~ s!^https?://[^/]+/!/!;
                $c->log->debug("Login::index auth ok, redirecting to $target");
                NGCP::Panel::Utils::Message::info(
                    c    => $c,
                    desc => $c->loc('Password successfully changed'),
                );
                $c->response->redirect($target);
            }
        } else {
            $c->log->warn("invalid http login from '".$c->qs($c->req->address)."'");
            $c->log->debug("Login::index auth failed");
            $form->add_form_error($c->loc('Invalid username/password'));
        }
    } else {
        # initial get
    }

    if ($form->has_errors) {
        my $request_ip = $c->request->address;
        $c->log->error("NGCP Panel Password Change failed realm=$realm ip=" . $c->qs($request_ip));
    }

    $c->stash(
        form => $form,
        realm => $realm,
        template => 'login/change_password.tt',
    );
}

1;

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Controller::Login - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
