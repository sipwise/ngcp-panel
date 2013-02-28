package NGCP::Panel::Controller::Domain;
use Moose;
use namespace::autoclean;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Domain;

=head1 NAME

NGCP::Panel::Controller::Domain - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub list :Chained('/') :PathPart('domain') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $domains = [
        {id => 1, domain => '1.example.org'},
        {id => 2, domain => '2.example.org'},
        {id => 3, domain => '3.example.org'},
        {id => 4, domain => '4.example.org'},
        {id => 5, domain => '5.example.org'},
        {id => 6, domain => '6.example.org'},
    ];
    $c->stash(domains => $domains);
    $c->stash(template => 'domain/list.tt');
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Domain->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Domain successfully created!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub search :Chained('list') :PathPart('search') Args(0) {
    my ($self, $c) = @_;

    $c->flash(messages => [{type => 'info', text => 'Domain search not implemented!'}]);
    $c->response->redirect($c->uri_for());
}

sub base :Chained('/domain/list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $domain_id) = @_;

    unless($domain_id && $domain_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid domain id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    # TODO: fetch details of domain from model
    my @rfilter = grep { $_->{id} == $domain_id } @{ $c->stash->{domains} };
    $c->stash(domain =>  shift @rfilter);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Domain->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{domain},
        action => $c->uri_for($c->stash->{domain}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Domain successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    # $c->model('Provisioning')->domain($c->stash->{domain}->{id})->delete;
    $c->flash(messages => [{type => 'info', text => 'Domain delete not implemented!'}]);
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
