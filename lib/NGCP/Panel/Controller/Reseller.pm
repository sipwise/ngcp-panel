package NGCP::Panel::Controller::Reseller;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Reseller;
use NGCP::Panel::Utils;

use Data::Printer;

=head1 NAME

NGCP::Panel::Controller::Reseller - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub list_reseller :Chained('/') :PathPart('reseller') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(
        resellers => $c->model('billing')
            ->resultset('resellers'),
        template => 'reseller/list.tt'
    );
    NGCP::Panel::Utils::check_redirect_chain(c => $c);
}

sub root :Chained('list_reseller') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list_reseller') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $resellers = $c->stash->{resellers};
    $c->forward(
        '/ajax_process_resultset', [
            $resellers,
            [qw(id contract_id name status)],
            [ 1, 2, 3 ]
        ]
    );
    $c->detach($c->view('JSON'));
    return;
}

sub create :Chained('list_reseller') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    # TODO: check in session if contract has just been created, and set it
    # as default value

    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Reseller->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, 
        form => $form, 
        fields => [qw/contract.create/], 
        back_uri => $c->uri_for('create')
    );
    # TODO: preserve the current "reseller" object for continuing editing
    # when coming back from /contract/create

    if($form->validated) {
        try {
            delete $form->params->{save};
            $form->params->{contract_id} = delete $form->params->{contract}->{id};
            delete $form->params->{contract};
            $c->model('billing')->resultset('resellers')->create($form->params);
            $c->flash(messages => [{type => 'success', text => 'Reseller successfully created.'}]);
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Creating reseller failed.'}]);
        }
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
}

sub base :Chained('list_reseller') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $reseller_id) = @_;

    unless($reseller_id && $reseller_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid reseller id detected.'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(reseller => $c->stash->{resellers}->find({id => $reseller_id}));
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Reseller->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : {$c->stash->{reseller}->get_inflated_columns},
        action => $c->uri_for($c->stash->{reseller}->get_column('id'), 'edit'),
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form, fields => [qw/contract.create/], 
        back_uri => $c->uri_for($c->stash->{reseller}->get_column('id'), 'edit')
    );

    if($posted && $form->validated) {
        try {
            my $form_values = $form->value;
            $form_values->{contract_id} = delete $form_values->{contract}{id};
            delete $form_values->{contract};
            $c->stash->{reseller}->update($form_values);            
            $c->flash(messages => [{type => 'success', text => 'Reseller successfully changed.'}]);
            delete $c->session->{contract_id};
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Updating reseller failed.'}]);
        }
        $c->response->redirect($c->uri_for());
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);

    $c->session(contract_id => $c->stash->{reseller}->get_column('contract_id'));

    return;
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{reseller}->delete;
        $c->flash(messages => [{type => 'success', text => 'Reseller successfully deleted.'}]);
    } catch($e) {
        $c->log->error($e);
        $c->flash(messages => [{type => 'error', text => 'Deleting reseller failed.'}]);
    }
    $c->response->redirect($c->uri_for());
}

sub ajax_contract :Chained('list_reseller') :PathPart('ajax_contract') :Args(0) {
    my ($self, $c) = @_;
  
    my $contract_id = $c->session->{contract_id};

    my @used_contracts = map { 
        $_->get_column('contract_id') unless(
            $contract_id && 
            $contract_id == $_->get_column('contract_id')
        )
    } $c->stash->{resellers}->all;
    my $free_contracts = $c->model('billing')
        ->resultset('contracts')
        ->search_rs({
            id => { 'not in' => \@used_contracts }
        });
    
    $c->forward("/ajax_process_resultset", [ 
        $free_contracts,
        ["id","contact_id","external_id","status"],
        [1,2,3]
    ]);
    
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
