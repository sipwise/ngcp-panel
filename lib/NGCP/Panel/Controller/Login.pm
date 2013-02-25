package NGCP::Panel::Controller::Login;

use Moose;
use namespace::autoclean;
BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Login;

=head1 NAME

NGCP::Panel::Controller::Login - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path Form {
    my ( $self, $c, $realm ) = @_;

    $c->log->debug("*** Login::index");
    $realm = 'subscriber' 
        unless($realm and ($realm eq 'admin' or $realm eq 'reseller'));

    my $form = NGCP::Panel::Form::Login->new;
    $form->process(
        posted => ($c->req->method eq 'POST'),
        params => $c->request->params,
    );

    if($form->validated) {
        print ">>>>>> login form validated\n";
        my $user = $form->field('username');
        my $pass = $form->field('password');
        $c->log->debug("*** Login::index user=$user, pass=$pass, realm=$realm");
        if($c->authenticate({ username => $user, password => $pass }, $realm)) {
            # auth ok
            my $target = $c->session->{'target'} || '/';
            delete $c->session->{target};
            $c->log->debug("*** Login::index auth ok, redirecting to $target");
            $c->response->redirect($target);
        } else {
            $c->log->debug("*** Login::index auth failed");
            $c->stash->{error}->{message} = 'login failed';
        }
    } elsif($c->req->method eq 'POST') {
        print ">>>>>> login form NOT validated\n";
        $c->stash->{error}->{message} = 'invalid form';
    } else {
        # initial get
    }

    $c->stash(form => $form);
    $c->stash(realm => $realm);
    $c->stash(template => 'login.tt');
}


=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
