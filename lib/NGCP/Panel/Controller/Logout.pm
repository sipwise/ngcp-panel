package NGCP::Panel::Controller::Logout;
use NGCP::Panel::Utils::Generic qw(:all);
use Moose;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

NGCP::Panel::Controller::Logout - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path {
    my ( $self, $c, $realm ) = @_;

    $c->logout;
    $c->response->redirect($c->uri_for('/login'));
}


=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


1;
# vim: set tabstop=4 expandtab:
