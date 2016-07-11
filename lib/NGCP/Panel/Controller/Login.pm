package NGCP::Panel::Controller::Login;

use warnings;
use strict;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form::Login;

sub index :Path Form {
    my ( $self, $c, $realm ) = @_;

    $realm = 'subscriber' 
        unless($realm && $realm eq 'admin');

    my $posted = ($c->req->method eq 'POST');
    my $form = NGCP::Panel::Form::Login->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => { username => $c->stash->{username} },
    );

    if($posted && $form->validated) {
        $c->log->debug("login form validated");
        my $user = $form->field('username')->value;
        my $pass = $form->field('password')->value;
        $c->log->debug("*** Login::index user=$user, pass=$pass, realm=$realm");
        my $res;
        if($realm eq 'admin') {
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
                }, 
                $realm);
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
