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

sub index :Path {
    my ( $self, $c, $realm ) = @_;

    $c->log->debug("*** Login::index");

    my $user = $c->req->params->{username};
    my $pass = $c->req->params->{password};

    $realm = 'subscriber' 
        unless($realm and ($realm eq 'admin' or $realm eq 'reseller'));

    if($user and $pass) {
        $c->log->debug("*** Login::index user=$user, pass=$pass, realm=$realm");
        if($c->authenticate({ username => $user, password => $pass }, $realm)) {
            # auth ok
            my $target = $c->session->{'target'} || '/';
            delete $c->session->{target};
            $c->log->debug("*** Login::index auth ok, redirecting to $target");
            $c->response->redirect($target);
        } else {
            $c->log->debug("*** Login::index auth failed");
        }
    } else {
        $c->log->debug("*** Login::index incomplete creds");
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
