package NGCP::Panel::Controller::Contract;
use Moose;
use namespace::autoclean;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Contract;

=head1 NAME

NGCP::Panel::Controller::Contract - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub list :Chained('/') :PathPart('contract') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $contracts = [
        {id => 1, contact_id => 1, billing_profile_id => 1, status => 'active'},
        {id => 2, contact_id => 2, billing_profile_id => 2, status => 'pending'},
        {id => 3, contact_id => 3, billing_profile_id => 3, status => 'active'},
        {id => 4, contact_id => 4, billing_profile_id => 4, status => 'terminated'},
        {id => 5, contact_id => 5, billing_profile_id => 5, status => 'locked'},
        {id => 6, contact_id => 6, billing_profile_id => 6, status => 'active'},
    ];
    $c->stash(contracts => $contracts);
    $c->stash(template => 'contract/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Contract->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contract successfully created!'}]);
        if($c->session->{redirect_target}) {
            # TODO: post back to redirect-target, so we can continue processing their form?
            $c->response->redirect($c->session->{redirect_target});
            return;
        }
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub search :Chained('list') :PathPart('search') Args(0) {
    my ($self, $c) = @_;

    $c->flash(messages => [{type => 'info', text => 'Contract search not implemented!'}]);
    $c->response->redirect($c->uri_for());
}

sub base :Chained('/contract/list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contract_id) = @_;

    unless($contract_id && $contract_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid contract id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    # TODO: fetch details of contract from model
    my @rfilter = grep { $_->{id} == $contract_id } @{ $c->stash->{contracts} };
    $c->stash(contract =>  shift @rfilter);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Contract->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{contract},
        action => $c->uri_for($c->stash->{contract}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contract successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    # $c->model('Provisioning')->contract($c->stash->{contract}->{id})->delete;
    $c->flash(messages => [{type => 'info', text => 'Contract delete not implemented!'}]);
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
