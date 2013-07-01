package NGCP::Panel::Controller::Rewrite;
use Sipwise::Base;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::RewriteRuleSet;
use NGCP::Panel::Form::RewriteRule;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub set_list :Chained('/') :PathPart('rewrite') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    $c->stash(template => 'rewrite/set_list.tt');
}

sub set_root :Chained('set_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub set_ajax :Chained('set_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('provisioning')->resultset('voip_rewrite_rule_sets');
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "name", "description"],
                 [1,2]]);
    
    $c->detach( $c->view("JSON") );
}

sub set_base :Chained('set_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $set_id) = @_;

    unless($set_id && $set_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid rewrite rule set id detected!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->model('provisioning')->resultset('voip_rewrite_rule_sets')->find($set_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Rewrite rule set does not exist!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }
    $c->stash(set_result => $res);
}

sub set_edit :Chained('set_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::RewriteRuleSet->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action('/rewrite/set_edit'),
        item   => $c->stash->{set_result},
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Rewrite Rule Set successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub set_delete :Chained('set_base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{set_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Rewrite Rule Set successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->uri_for());
}

sub set_create :Chained('set_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::RewriteRuleSet->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/rewrite/set_create'),
        item   => $c->model('provisioning')->resultset('voip_rewrite_rule_sets')->new_result({}),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Rewrite Rule Set successfully created!'}]);
        $c->response->redirect($c->uri_for_action('/rewrite/set_root'));
        return;
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub rules_list :Chained('set_base') :PathPart('rules') :CaptureArgs(0) {
    my ( $self, $c ) = @_;
    
    my $rules_rs = $c->stash->{set_result}->voip_rewrite_rules;
    $c->stash(rules_rs => $rules_rs);
    $c->stash(rules_uri => $c->uri_for_action("/rewrite/rules_root", [$c->req->captures->[0]]));

    $c->stash(template => 'rewrite/rules_list.tt');
}

sub rules_root :Chained('rules_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    
    my $rules_rs    = $c->stash->{rules_rs};
    my $param_move  = $c->req->params->{move};
    my $param_where = $c->req->params->{where};
    
    my $elem = $rules_rs->find($param_move)
        if ($param_move && $param_move->is_integer && $param_where);
    if($elem) {
        my $use_next = ($param_where eq "down") ? 1 : 0;
        my $swap_elem = $rules_rs->search({
            field => $elem->field,
            direction => $elem->direction,
            priority => { ($use_next ? '>' : '<') => $elem->priority },
        },{
            order_by => {($use_next ? '-asc' : '-desc') => 'priority'}
        })->first;
        if ($swap_elem) {
            my $tmp_priority = $swap_elem->priority;
            $swap_elem->priority($elem->priority);
            $elem->priority($tmp_priority);
            $swap_elem->update;
            $elem->update;
        }
    }
    
    my @caller_in = $rules_rs->search({
        field => 'caller',
        direction => 'in',
    },{
        order_by => 'priority',
    })->all;
    
    my @callee_in = $rules_rs->search({
        field => 'callee',
        direction => 'in',
    },{
        order_by => 'priority',
    })->all;
    
    my @caller_out = $rules_rs->search({
        field => 'caller',
        direction => 'out',
    },{
        order_by => 'priority',
    })->all;
    
    my @callee_out = $rules_rs->search({
        field => 'callee',
        direction => 'out',
    },{
        order_by => 'priority',
    })->all;
    
    for my $row (@caller_in, @callee_in, @caller_out, @callee_out) {
        my $mp = $row->match_pattern;
        my $rp = $row->replace_pattern;
        $mp =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
        $rp =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
        $row->match_pattern($mp);
        $row->replace_pattern($rp);
    }
    
    $c->stash(rules => {
        caller_in  => \@caller_in,
        callee_in  => \@callee_in,
        caller_out => \@caller_out,
        callee_out => \@callee_out,
    });
    return;
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && $rule_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid rewrite rule id detected!'}]);
        $c->response->redirect($c->stash->{rules_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{rules_rs}->find($rule_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Rewrite rule does not exist!'}]);
        $c->response->redirect($c->stash->{rules_uri});
        $c->detach;
        return;
    }
    $c->stash(rule_result => $res);
}

sub rules_edit :Chained('rules_base') :PathPart('edit') {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::RewriteRule->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        action => $c->uri_for_action('/rewrite/rules_edit', $c->req->captures),
        item   => $c->stash->{rule_result},
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Rewrite Rule successfully changed!'}]);
        $c->response->redirect($c->stash->{rules_uri});
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub rules_delete :Chained('rules_base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{rule_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Rewrite Rule successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->stash->{rules_uri});
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::RewriteRule->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/rewrite/rules_create', $c->req->captures),
        item   => $c->stash->{rules_rs}->new_result({}),
    );
    if($form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Rewrite Rule successfully created!'}]);
        $c->response->redirect($c->stash->{rules_uri});
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

NGCP::Panel::Controller::Rewrite - Manage Rewrite Rules

=head1 DESCRIPTION

Show/Edit/Create/Delete Rewrite Rule Sets.

Show/Edit/Create/Delete Rewrite Rules within Rewrite Rule Sets.

=head1 METHODS

=head2 set_list

Basis for provisioning.voip_rewrite_rule_sets.

=head2 set_root

Display rewrite rule sets through F<rewrite/set_list.tt> template.

=head2 set_ajax

Get provisioning.voip_rewrite_rule_sets from the database and
output them as JSON.
The format is meant for parsing with datatables.

=head2 set_base

Fetch a provisioning.voip_rewrite_rule_set from the database by its id.

=head2 set_edit

Show a modal to edit a rewrite rule set determined by L</set_base>.
The form used is L<NGCP::Panel::Form::RewriteRuleSet>.

=head2 set_delete

Delete a rewrite rule set determined by L</set_base>.

=head2 set_create

Show a modal to create a new rewrite rule set using the form
L<NGCP::Panel::Form::RewriteRuleSet>.

=head2 rules_list

Basis for provisioning.voip_rewrite_rules. Chained from L</set_base> and
therefore handles only rules for a certain rewrite rule set.

=head2 rules_root

Display rewrite rule sets through F<rewrite/rules_list.tt> template.
The rules are stashed to rules hashref which contains the keys
"caller_in", "callee_in", "caller_out", "callee_out".

It swaps priority of two elements if "move" and "where" GET params are set.

It modifies match_pattern and replace_pattern field to a certain output format
using regex.

=head2 rules_base

Fetch a rewrite rule from the database by its id. Will only find rules under
the current rule_set.

=head2 rules_edit

Show a modal to edit a rewrite rule determined by L</rules_base>.
The form used is L<NGCP::Panel::Form::RewriteRule>.

=head2 rules_delete

Delete a rewrite rule determined by L</rules_base>.

=head2 rules_create

Show a modal to create a new rewrite rule using the form
L<NGCP::Panel::Form::RewriteRule>.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
