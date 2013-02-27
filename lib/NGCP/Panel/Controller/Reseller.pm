package NGCP::Panel::Controller::Reseller;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Reseller;

=head1 NAME

NGCP::Panel::Controller::Reseller - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub reseller : Path Chained('/') CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $resellers = [
        {id => 1, contract_id => 1, name => 'reseller 1', status => 'active'},
        {id => 2, contract_id => 2, name => 'reseller 2', status => 'active'},
        {id => 3, contract_id => 3, name => 'reseller 3', status => 'active'},
        {id => 4, contract_id => 4, name => 'reseller 4', status => 'locked'},
        {id => 5, contract_id => 5, name => 'reseller 5', status => 'terminated'},
        {id => 6, contract_id => 6, name => 'reseller 6', status => 'active'},
    ];
    $c->stash(resellers => $resellers);


    $c->stash(template => 'reseller.tt');
}


sub edit : Chained('reseller') PathPart('edit') :Args(1) {
    my ( $self, $c, $reseller_id ) = @_;

    my @reseller = grep { $_->{id} == $reseller_id } @{ $c->stash->{resellers} };
    use Data::Printer;
    p @reseller;
    my $form = NGCP::Panel::Form::Reseller->new;
    $form->process(
        posted => ($c->req->method eq 'POST'),
        params => $reseller[0],
        action => $c->uri_for('/reseller/save'),
    );
    $c->stash(form => $form);
    $c->stash(edit => $reseller[0]);
}

sub save : Path('/reseller/save') :Args(0) {
    my ( $self, $c) = @_;
}

sub delete : Path('/reseller/delete') :Args(1) {
    my ( $self, $c, $reseller_id) = @_;
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
