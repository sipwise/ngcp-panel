package NGCP::Panel::Controller::Login;

use warnings;
use strict;

use parent 'Catalyst::Controller';
use Redis;
use TryCatch;
use UUID;

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Auth;

sub login_index :Path Form {
    my ( $self, $c, $realm ) = @_;

    $realm = 'subscriber'
        unless($realm && $realm eq 'admin');

    my $posted = ($c->req->method eq 'POST');
    my $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Login", $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => { username => $c->stash->{username} },
    );

    if($posted && $form->validated) {
        $c->log->debug("login form validated");
        my $user = $form->field('username')->value;
        my $pass = $form->field('password')->value;
        $c->log->debug("*** Login::index user=$user, pass=****, realm=$realm");
        my $res;
        if($realm eq 'admin') {
            $res = NGCP::Panel::Utils::Auth::perform_auth($c, $user, $pass, 'admin', 'admin_bcrypt');
        } elsif($realm eq 'subscriber') {
            my ($u, $d, $t) = split /\@/, $user;
            if(defined $t) {
                # in case username is an email address
                $u = $u . '@' . $d;
                $d = $t;
            }
            unless(defined $d) {
                $d = $c->req->uri->host;
            }
            $res = NGCP::Panel::Utils::Auth::perform_subscriber_auth($c, $u, $d, $pass);
        }

        if($res) {
            # auth ok
            $c->session->{user_tz} = undef;  # reset to reload from db
            $c->session->{user_tz_name} = undef;  # reset to reload from db
            my $target = $c->session->{'target'} || '/';
            delete $c->session->{target};
            $target =~ s!^https?://[^/]+/!/!;
            $c->log->debug("*** Login::index auth ok, redirecting to $target");
            $c->response->redirect($target);
            return;
        } else {
            $c->log->warn("invalid http login from '".$c->qs($c->req->address)."'");
            $c->log->debug("*** Login::index auth failed");
            $form->add_form_error($c->loc('Invalid username/password'));
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
                        # don't clear password, a user might just have guessed it and
                        # could then block the legit user out
                        my ($uuid_bin, $uuid_string);
                        UUID::generate($uuid_bin);
                        UUID::unparse($uuid_bin, $uuid_string);
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
                        $username = $admin->login;
                        if ($redis->exists("password_reset:admin::$username")) {
                            NGCP::Panel::Utils::Message::info(
                                c    => $c,
                                desc => $c->loc('A password reset attempt has been made already recently, please check your email'),
                            );
                        }
                        else {
                            $redis->hset("password_reset:admin::$username", 'token', $uuid_string);
                            $redis->expire("password_reset:admin::$username", 300);
                            $redis->hset("password_reset:admin::$uuid_string", 'user', $username);
                            $redis->hset("password_reset:admin::$uuid_string", 'ip', $c->req->address);
                            $redis->expire("password_reset:admin::$uuid_string", 300);
                            
                            my $url = NGCP::Panel::Utils::Email::rewrite_url(
                                $c->config->{contact}->{external_base_url},
                                $c->uri_for_action('/login/recover_password')->as_string);
                            $url .= '?token=' . $uuid_string;
                            
                            NGCP::Panel::Utils::Email::admin_password_reset($c, $admin, $url);

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
