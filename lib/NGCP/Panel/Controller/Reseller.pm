package NGCP::Panel::Controller::Reseller;
use Moose;
use namespace::autoclean;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Reseller;

=head1 NAME

NGCP::Panel::Controller::Reseller - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub list :Chained('/') :PathPart('reseller') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $resellers = [
        {id => 1, contract => 1, name => 'reseller 1', status => 'active'},
        {id => 2, contract => 2, name => 'reseller 2', status => 'active'},
        {id => 3, contract => 3, name => 'reseller 3', status => 'active'},
        {id => 4, contract => 4, name => 'reseller 4', status => 'locked'},
        {id => 5, contract => 5, name => 'reseller 5', status => 'terminated'},
        {id => 6, contract => 6, name => 'reseller 6', status => 'active'},
    ];
    $c->stash(resellers => $resellers);
    $c->stash(template => 'reseller/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    # TODO: check if some create-button is clicked, then set
    # $c->session(redirect_target => $c->uri_for()); # <-- redirect back to here
    # somehow save form in session(?) so we can continue from here,
    # or maybe post from the redirect_target back here, with all values filled in already?


    my $form = NGCP::Panel::Form::Reseller->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Reseller successfully created!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub search :Chained('list') :PathPart('search') Args(0) {
    my ($self, $c) = @_;

    $c->flash(messages => [{type => 'info', text => 'Reseller search not implemented!'}]);
    $c->response->redirect($c->uri_for());
}

sub base :Chained('/reseller/list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $reseller_id) = @_;

    unless($reseller_id && $reseller_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid reseller id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    # TODO: fetch details of reseller from model
    my @rfilter = grep { $_->{id} == $reseller_id } @{ $c->stash->{resellers} };
    $c->stash(reseller =>  shift @rfilter);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Reseller->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{reseller},
        action => $c->uri_for($c->stash->{reseller}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Reseller successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    # $c->model('Provisioning')->reseller($c->stash->{reseller}->{id})->delete;
    $c->flash(messages => [{type => 'info', text => 'Reseller delete not implemented!'}]);
    $c->response->redirect($c->uri_for());
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
