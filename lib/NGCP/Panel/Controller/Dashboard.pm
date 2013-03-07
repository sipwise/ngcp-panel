package NGCP::Panel::Controller::Dashboard;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Widget;
use Data::Dumper;

=head1 NAME

NGCP::Panel::Controller::Dashboard - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

Dashboard index

=cut

sub index :Path :Args(0) {
    my ($self, $c) = @_;

    my $widget_templates = [];
    my $finder = NGCP::Panel::Widget->new;
    foreach($finder->instantiate_plugins($c)) {
        $_->handle($c);
        push @{ $widget_templates }, $_->template; 
    }
    
    $c->stash(widgets => $widget_templates);
    $c->stash(template => 'dashboard.tt');
    delete $c->session->{redirect_targets};
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
