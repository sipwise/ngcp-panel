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
#        $c->model('billing')->resultset('domains')->create({
#            domain => $form->field('domain')->value, });
        my $schema = $c->model('billing')->schema;
        $schema->provisioning($c->model('provisioning')->schema->connect);
        $schema->create_domain(
            {
                domain => $form->field('domain')->value,
                #id => 1,
            },
            1
        );
        $c->flash(messages => [{type => 'success', text => 'Domain successfully created!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
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

    my $res = $c->model('billing')->resultset('domains')->find($domain_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Domain does not exist!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash(domain => {$res->get_columns});
    $c->stash(domain_result => $res);
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
        
#        $c->model('billing')->resultset('domains')->search({
#                id => $c->stash->{domain}->{id},
#            })
        $c->stash->{'domain_result'}->update({
              domain => $form->field('domain')->value,
          });

        $c->flash(messages => [{type => 'success', text => 'Domain successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    unless ( defined($c->stash->{'domain_result'}) ) {
        return;
    }

    $c->stash->{'domain_result'}->delete;
#    $c->model('billing')->resultset('domains')->search({
#            id => $c->stash->{domain}->{id},
#        })->delete;
    
#    my $schema = $c->model('billing')->schema;
#    $schema->provisioning($c->model('provisioning')->schema->connect);
#    $schema->delete_domain({
#            domain => $c->stash->{domain}->{domain},
#            id     => $c->stash->{domain}->{id},
#        },
#        1,
#    );

    $c->flash(messages => [{type => 'success', text => 'Domain successfully deleted!'}]);
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('billing')->resultset('domains');
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "domain"],
                 [0,1]]);
    
    $c->detach( $c->view("JSON") );
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
