package NGCP::Panel::Controller::NCOS;
use Sipwise::Base;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::NCOSLevel;
use NGCP::Panel::Form::NCOSPattern;
use HTML::FormHandler;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub levels_list :Chained('/') :PathPart('ncos') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $dispatch_to = '_levels_resultset_' . $c->user->auth_realm;
    my $levels_rs = $self->$dispatch_to($c);
    $c->stash(levels_rs => $levels_rs);

    $c->stash(template => 'ncos/list.tt');
}

sub _levels_resultset_admin {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('ncos_levels');
    return $rs;
}

sub _levels_resultset_reseller {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('admins')
        ->find($c->user->id)->reseller->ncos_levels;
    return $rs;
}

sub root :Chained('levels_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('levels_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{levels_rs};
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "level", "mode", "description"],
                 ["level", "mode", "description"]]);
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('levels_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $level_id) = @_;

    unless($level_id && $level_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid NCOS Level id detected!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->stash->{levels_rs}->find($level_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'NCOS Level does not exist!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }
    $c->stash(level_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOSLevel->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action('/ncos/edit'),
        item   => $c->stash->{level_result},
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'NCOS Level successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{level_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'NCOS Level successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->uri_for());
}

sub create :Chained('levels_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::NCOSLevel->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/ncos/create'),
        item   => $c->stash->{levels_rs}->new_result({}),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'NCOS Level successfully created!'}]);
        $c->response->redirect($c->uri_for_action('/ncos/root'));
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub pattern_list :Chained('base') :PathPart('pattern') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $pattern_rs = $c->stash->{level_result}->ncos_pattern_lists;
    $c->stash(pattern_rs => $pattern_rs);
    $c->stash(pattern_base_uri =>
        $c->uri_for_action("/ncos/pattern_root", [$c->req->captures->[0]]));
    
    my $local_ac_form = HTML::FormHandler::Model::DBIC->new(field_list => [
        local_ac => { type => 'Boolean', label => 'Include local area code'},
        save => { type => 'Submit', value => 'Set', element_class => ['btn']},
        ],
        'widget_wrapper' => 'Bootstrap',
        form_element_class => ['form-horizontal', 'ngcp-quickform'],
    );
    $local_ac_form->process(
        posted => ($c->request->method eq 'POST') && defined $c->req->params->{local_ac},
        params => $c->request->params,
        item   => $c->stash->{level_result}
    );
    $c->stash(local_ac_form => $local_ac_form);
    if($local_ac_form->validated) {
        $c->response->redirect($c->stash->{pattern_base_uri});
        $c->detach;
        return;
    }

    $c->stash(template => 'ncos/pattern_list.tt');
}

sub pattern_root :Chained('pattern_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub pattern_ajax :Chained('pattern_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{pattern_rs};
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "pattern", "description"],
                 ["pattern", "description"]]);
    
    $c->detach( $c->view("JSON") );
}

sub pattern_base :Chained('pattern_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $pattern_id) = @_;

    unless($pattern_id && $pattern_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid NCOS Pattern id detected!'}]);
        $c->response->redirect($c->stash->{pattern_base_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{pattern_rs}->find($pattern_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Pattern does not exist!'}]);
        $c->response->redirect($c->stash->{pattern_base_uri});
        $c->detach;
        return;
    }
    $c->stash(pattern_result => $res);
}

sub pattern_edit :Chained('pattern_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::NCOSPattern->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action('/ncos/pattern_edit', $c->req->captures),
        item   => $c->stash->{pattern_result},
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Pattern successfully changed!'}]);
        $c->response->redirect($c->stash->{pattern_base_uri});
        return;
    }

    $c->stash(close_target => $c->stash->{pattern_base_uri});
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub pattern_delete :Chained('pattern_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        $c->stash->{pattern_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Pattern successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->stash->{pattern_base_uri});
}

sub pattern_create :Chained('pattern_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::NCOSPattern->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/ncos/pattern_create', $c->req->captures),
        item   => $c->stash->{pattern_rs}->new_result({}),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Pattern successfully created!'}]);
        $c->response->redirect($c->stash->{pattern_base_uri});
        return;
    }

    $c->stash(close_target => $c->stash->{pattern_base_uri});
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}


__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::NCOS - manage NCOS levels/patterns

=head1 DESCRIPTION

Show/Edit/Create/Delete NCOS Levels.

Show/Edit/Create/Delete Number patterns.

=head1 METHODS

=head2 auto

Grants access to admin and reseller role.

=head2 levels_list

Basis for billing.ncos_levels.

=head2 root

Display NCOS Levels through F<ncos/list.tt> template.

=head2 ajax

Get billing.ncos_levels from db and output them as JSON.
The format is meant for parsing with datatables.

=head2 base

Fetch a billing.ncos_levels row from the database by its id.
The resultset is exported to stash as "level_result".

=head2 edit

Show a modal to edit the NCOS Level determined by L</base>.

=head2 delete

Delete the NCOS Level determined by L</base>.

=head2 create

Show modal to create a new NCOS Level using the form
L<NGCP::Panel::Form::NCOSLevel>.

=head2 pattern_list

Basis for billing.ncos_pattern_list.
Fetches all patterns related to the level determined by L</base> and stashes
the resultset under "pattern_rs".

=head2 pattern_root

Display NCOS Number Patterns through F<ncos/pattern_list.tt> template.

=head2 pattern_ajax

Get patterns from db using the resultset from L</pattern_list> and
output them as JSON. The format is meant for parsing with datatables.

=head2 pattern_base

Fetch a billing.ncos_pattern_list row from the database by its id.
The resultset is exported to stash as "pattern_result".

=head2 pattern_edit

Show a modal to edit the Number Pattern determined by L</pattern_base>.

=head2 pattern_delete

Delete the Number Pattern determined by L</pattern_base>.

=head2 pattern_create

Show modal to create a new Number Pattern for the current Level using the form
L<NGCP::Panel::Form::NCOSPattern>.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
