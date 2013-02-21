package NGCP::Panel::Controller::Dashboard;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Widget;

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
    my ( $self, $c ) = @_;

    my $widget_templates = [];
    my $finder = NGCP::Panel::Widget->new;
    foreach($finder->list_plugins) {
        my $widget = NGCP::Panel::Widget->new;
        $widget->load_plugin($_);
        $widget->handle($c);
        push @{ $widget_templates }, $widget->template; 
    }
    
    $c->stash(widgets => $widget_templates);
    $c->stash(template => 'dashboard.tt');
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
