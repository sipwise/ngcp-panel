package NGCP::Panel::Controller::Logout;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use parent 'Catalyst::Controller';

=head1 NAME

NGCP::Panel::Controller::Logout - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub logout_index :Path {
    my ( $self, $c, $realm ) = @_;

    $c->logout;
    my $redirect = $c->req->params->{redirect} // 1;
    $c->response->redirect($c->uri_for('/login')) if $redirect;
}

sub ajax_logout :Chained('/') :PathPart('ajax_logout') :Args(0) {
    my ( $self, $c ) = @_;

    delete $c->session->{framed} if ($c->session->{framed});
    $c->logout;
    $c->response->status(200);
    $c->response->content_type('application/json');
    $c->response->body('');
    $c->detach( $c->view("JSON") );
}

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


1;
# vim: set tabstop=4 expandtab:
