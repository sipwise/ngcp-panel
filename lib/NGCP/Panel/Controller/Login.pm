package NGCP::Panel::Controller::Login;

use Moose;
use namespace::autoclean;
BEGIN { extends 'Catalyst::Controller'; }

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

    my $user = $c->request->param('username');
    my $pass = $c->request->param('password');
    $c->log->debug("*** Login::index user=$user, pass=$pass, realm=$realm");

    if($user && $pass) {
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
    } else {
        if($user || $pass) {
            $c->stash->{error}->{message} = 'invalid form';
        }
    }

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
