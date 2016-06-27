package NGCP::Panel::Controller::Login;

use warnings;
use strict;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form::Login;
use NGCP::Panel::Utils::Admin;
use Crypt::Eksblowfish::Bcrypt qw/bcrypt_hash en_base64 de_base64/;

sub index :Path Form {
    my ( $self, $c, $realm ) = @_;

    $realm = 'subscriber' 
        unless($realm && $realm eq 'admin');
    if($c->request->params->{realm}){
        $realm = $c->request->params->{realm};
    }
    $c->session->{realm} = $realm;
    my $posted = ($c->req->method eq 'POST');
    my $form = NGCP::Panel::Form::Login->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => { username => $c->stash->{username} },
    );

    if($posted && $form->validated) {
        $c->log->debug("login form validated");
        my $user = $form->field('username')->value // '';
        my $pass = $form->field('password')->value // '';
        $c->log->debug("*** Login::index user=$user, pass=****, realm=$realm");
        my $res;
        if($realm eq 'admin') {
            my $dbadmin = $c->model('DB')->resultset('admins')->find({
                login => $user,
                is_active => 1,
            });
            if(defined $dbadmin && defined $dbadmin->saltedpass) {
                $c->log->debug("login via bcrypt");
                my ($db_b64salt, $db_b64hash) = split /\$/, $dbadmin->saltedpass;
                my $salt = de_base64($db_b64salt);
                my $usr_b64hash = en_base64(bcrypt_hash({
                    key_nul => 1,
                    cost => NGCP::Panel::Utils::Admin::get_bcrypt_cost(),
                    salt => $salt,
                }, $pass));
                # fetch again to load user into session etc (otherwise we could
                # simply compare the two hashes here :(
                $res = $c->authenticate(
                    {
                        login => $user,
                        saltedpass => $db_b64salt . '$' . $usr_b64hash,
                        'dbix_class' => {
                            searchargs => [{
                                -and => [
                                    login => $user,
                                    is_active => 1,
                                ],
                            }],
                        }
                    }, 'admin_bcrypt'
                );
            } elsif(defined $dbadmin) { # we already know if the username is wrong, no need to check again

                # check md5 and migrate over to bcrypt on success
                $c->log->debug("login via md5");
                $res = $c->authenticate(
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
                    }, 'admin');

                if($res) {
                    # login ok, time to move user to bcrypt hashing
                    $c->log->debug("migrating to bcrypt");
                    my $saltedpass = NGCP::Panel::Utils::Admin::generate_salted_hash($pass);
                    $dbadmin->update({
                        md5pass => undef,
                        saltedpass => $saltedpass,
                    });
                }

            }
        } elsif($realm eq 'subscriber') {
            my $dbr = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                'voip_subscriber.status' => 'active',
                'contract.status'        => 'active',
                'domain.domain'          => { '!=', undef },
                'webpassword'            => $pass ? ( $pass ) : { '!=', undef },
                'webusername'            => $user ? ( $user ) : { '!=', undef } ,
            }, {
                join => ['domain', 'contract', 'voip_subscriber'],
            })->first;
            use Data::Dumper;
            $c->log->debug(Dumper({$dbr->get_inflated_columns}));
            $user = $dbr->webusername.'@'.$dbr->domain->domain;
            $pass = $dbr->webpassword;
            my ($u, $d, $t) = split /\@/, $user;
            if(defined $t) {
                # in case username is an email address
                $u = $u . '@' . $d;
                $d = $t;
            }
            unless(defined $d) {
                $d = $c->req->uri->host;
            }
            my $authrs = $c->model('DB')->resultset('provisioning_voip_subscribers')->search({
                webusername => $u,
                webpassword => $pass,
                'voip_subscriber.status' => 'active',
                'domain.domain' => $d,
                'contract.status' => 'active',
            }, {
                join => ['domain', 'contract', 'voip_subscriber'],
            });
            $res = $c->authenticate(
                {
                    webusername => $u, 
                    webpassword => $pass,
                    'dbix_class' => {
                        resultset => $authrs
                    }
                }, 
                $realm);
        }

        if($res) {
            # auth ok
            my $target = $c->session->{'target'} || '/';
            delete $c->session->{target};
            $target =~ s!^https?://[^/]+/!/!;
            $c->log->debug("*** Login::index auth ok, redirecting to $target");
            $c->response->redirect($target);
            return;
        } else {
            $c->log->warn("invalid http login from '".$c->req->address."'");
            $c->log->debug("*** Login::index auth failed");
            $form->add_form_error($c->loc('Invalid username/password'));
        }
    } else {
        # initial get
    }

    if ($form->has_errors) {
        my $request_ip = $c->request->address;
        $c->log->error("NGCP Panel Login failed realm=$realm ip=$request_ip");
    }

    $c->stash(form => $form);
    $c->stash(realm => $realm);
    $c->stash(template => 'login/login.tt');
}

__PACKAGE__->meta->make_immutable;

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
