package NGCP::Panel::Controller::Peering;
use Sipwise::Base;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Utils;
use NGCP::Panel::Form::PeeringGroup;
use NGCP::Panel::Form::PeeringRule;
use NGCP::Panel::Form::PeeringServer;

sub group_list :Chained('/') :PathPart('peering') :CaptureArgs(0) :Args(0) {
    my ( $self, $c ) = @_;
    
    NGCP::Panel::Utils::check_redirect_chain(c => $c);

    $c->stash(has_edit => 1);
    $c->stash(has_delete => 1);
    $c->stash(template => 'peering/list.tt');
}

sub root :Chained('group_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('group_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->model('provisioning')->resultset('voip_peer_groups');
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "name", "priority", "description", "peering_contract_id"],
                 [1,2,4]]);
    
    $c->detach( $c->view("JSON") );
}

sub base :Chained('group_list') :PathPart('') :CaptureArgs(1) :Args(0) {
    my ($self, $c, $group_id) = @_;

    unless($group_id && $group_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid group id detected!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    my $res = $c->model('provisioning')->resultset('voip_peer_groups')->find($group_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Peering Group does not exist!'}]);
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }
    $c->stash(group => {$res->get_columns});
    $c->stash->{group}->{'contract.id'} = $res->peering_contract_id;
    $c->stash(group_result => $res);
}

sub edit :Chained('base') :PathPart('edit') {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringGroup->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{group},
        action => $c->uri_for_action('/peering/edit', [$c->req->captures->[0]])
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form, fields => [qw/contract.create/],
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{group_result}->update($form->custom_get_values);
            $c->flash(messages => [{type => 'success', text => 'Peering Group successfully changed!'}]);
        } catch (DBIx::Class::Exception $e) {
            $c->flash(messages => [{type => 'error', text => 'Update of peering group failed.'}]);
            $c->log->info("Update failed: " . $e);
        };
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{group_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Peering Group successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->uri_for());
}

sub create :Chained('group_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::PeeringGroup->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c, form => $form, fields => [qw/contract.create/],
        back_uri => $c->req->uri,
    );
    if($form->validated) {
        my $formdata = $form->custom_get_values;
        try {
            $c->model('provisioning')->resultset('voip_peer_groups')->create(
                $formdata );
            $c->flash(messages => [{type => 'success', text => 'Peering group successfully created!'}]);
        } catch (DBIx::Class::Exception $e) {
            $c->flash(rules_messages => [{type => 'error', text => 'Creation of peering group failed.'}]);
            $c->log->info("Create failed: " . $e);
        };
        $c->response->redirect($c->uri_for_action('/peering/root'));
        return;
    }

    $c->stash(close_target => $c->uri_for_action('/peering/root'));
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub servers_list :Chained('base') :PathPart('servers') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $sr_list_uri = $c->uri_for_action(
        '/peering/servers_root', [$c->req->captures->[0]]);
    $c->stash(sr_list_uri => $sr_list_uri);
    $c->stash(template => 'peering/servers_rules.tt');
}

sub servers_root :Chained('servers_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub servers_ajax :Chained('servers_list') :PathPart('s_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_hosts;
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "name", "ip", "host", "port", "transport", "weight"],
                 [1,2,3,4,6]]);
    
    $c->detach( $c->view("JSON") );
}

sub servers_create :Chained('servers_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $form = NGCP::Panel::Form::PeeringServer->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/peering/servers_create', [$c->req->captures->[0]]),
    );
    if($form->validated) {
        try {
            $c->stash->{group_result}->voip_peer_hosts->create( $form->fif );
            $c->flash(messages => [{type => 'success', text => 'Peering server successfully created!'}]);
        } catch (DBIx::Class::Exception $e) {
            $c->flash(messages => [{type => 'error', text => 'Creation of Peering server failed.'}]);
            $c->log->info("Create failed: " . $e);
        };
        $c->response->redirect($c->stash->{sr_list_uri});
        return;
    }

    $c->stash(close_target => $c->stash->{sr_list_uri});
    $c->stash(servers_create_flag => 1);
    $c->stash(servers_form => $form);
}

sub servers_base :Chained('servers_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $server_id) = @_;

    unless($server_id && $server_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid peering sever (host) id detected!'}]);
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{group_result}->voip_peer_hosts->find($server_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Peering Server does not exist!'}]);
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }
    $c->stash(server => {$res->get_columns});
    $c->stash(server_result => $res);
}

sub servers_edit :Chained('servers_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringServer->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{server},
        action => $c->uri_for_action('/peering/servers_edit', $c->req->captures)
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{server_result}->update($form->fif);
            $c->flash(messages => [{type => 'success', text => 'Peering Server successfully changed!'}]);
        } catch (DBIx::Class::Exception $e) {
            $c->flash(messages => [{type => 'error', text => 'Updating of Peering server failed.'}]);
            $c->log->info("Update failed: " . $e);
        };
        
        $c->response->redirect($c->stash->{sr_list_uri});
        return;
    }

    $c->stash(close_target => $c->stash->{sr_list_uri});
    $c->stash(servers_form => $form);
    $c->stash(servers_edit_flag => 1);
}

sub servers_delete :Chained('servers_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{server_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Peering Server successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(rules_messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->stash->{sr_list_uri});
}

sub servers_preferences :Chained('servers_base') :PathPart('preferences') :Args(0) {

}

sub rules_list :Chained('base') :PathPart('rules') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $sr_list_uri = $c->uri_for_action(
        '/peering/servers_root', [$c->req->captures->[0]]);
    $c->stash(sr_list_uri => $sr_list_uri);
    $c->stash(template => 'peering/servers_rules.tt');
}

sub rules_ajax :Chained('rules_list') :PathPart('r_ajax') :Args(0) {
    my ($self, $c) = @_;
    
    my $resultset = $c->stash->{group_result}->voip_peer_rules;
    
    $c->forward( "/ajax_process_resultset", [$resultset,
                 ["id", "callee_prefix", "callee_pattern", "caller_pattern", "description"],
                 [1,2,3,4]]);
    
    $c->detach( $c->view("JSON") );
}

sub rules_create :Chained('rules_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    
    my $form = NGCP::Panel::Form::PeeringRule->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for_action('/peering/rules_create', [$c->req->captures->[0]]),
    );
    if($form->validated) {
        try {
            $c->stash->{group_result}->voip_peer_rules->create( $form->fif );
            $c->flash(rules_messages => [{type => 'success', text => 'Peering rule successfully created!'}]);
        } catch (DBIx::Class::Exception $e) {
            $c->flash(rules_messages => [{type => 'error', text => 'Create failed.'}]);
            $c->log->info("Create failed: " . $e);
        };
        $c->response->redirect($c->stash->{sr_list_uri});
        return;
    }

    $c->stash(close_target => $c->stash->{sr_list_uri});
    $c->stash(rules_create_flag => 1);
    $c->stash(rules_form => $form);
}

sub rules_base :Chained('rules_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $rule_id) = @_;

    unless($rule_id && $rule_id->is_integer) {
        $c->flash(rules_messages => [{type => 'error', text => 'Invalid peering rule id detected!'}]);
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }

    my $res = $c->stash->{group_result}->voip_peer_rules->find($rule_id);
    unless(defined($res)) {
        $c->flash(rules_messages => [{type => 'error', text => 'Peering Rule does not exist!'}]);
        $c->response->redirect($c->stash->{sr_list_uri});
        $c->detach;
        return;
    }
    $c->stash(rule => {$res->get_columns});
    $c->stash(rule_result => $res);
}

sub rules_edit :Chained('rules_base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    
    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::PeeringRule->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{rule},
        action => $c->uri_for_action('/peering/rules_edit', $c->req->captures)
    );
    if($posted && $form->validated) {
        try {
            $c->stash->{rule_result}->update($form->fif);
            $c->flash(rules_messages => [{type => 'success', text => 'Peering Rule successfully changed!'}]);
        } catch (DBIx::Class::Exception $e) {
            $c->flash(rules_messages => [{type => 'error', text => 'Edit failed.'}]);
            $c->log->info("Update failed: " . $e);
        };
        $c->response->redirect($c->stash->{sr_list_uri});
        return;
    }

    $c->stash(close_target => $c->stash->{sr_list_uri});
    $c->stash(rules_form => $form);
    $c->stash(rules_edit_flag => 1);
}

sub rules_delete :Chained('rules_base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    
    try {
        $c->stash->{rule_result}->delete;
        $c->flash(rules_messages => [{type => 'success', text => 'Peering Rule successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(rules_messages => [{type => 'error', text => 'Delete failed.'}]);
        $c->log->info("Delete failed: " . $e);
    };
    $c->response->redirect($c->stash->{sr_list_uri});
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

NGCP::Panel::Controller::Peering - manage peering groups, servers, rules

=head1 DESCRIPTION

Create/Edit/Delete of peering groups.

Create/Edit/Delete of peering servers and peering rules within peering groups.

Management of peer_preferences within peering servers.

=head1 METHODS

=head2 group_list

basis for peering groups.

=head2 root

Display peering groups through F<peering/list.tt> template.

=head2 ajax

Get provisioning.voip_peer_groups from the database and output them as JSON.
The format is meant for parsing with datatables.

=head2 base

Fetch a provisioning.voip_peer_groups from the database by its id.
Add the field "contract.id" for easier parsing into the form (in L</edit>).

=head2 edit

Show a modal to edit a peering group.

=head2 delete

Delete a peering group.

=head2 create

Show a modal to create a new peering group.

=head2 servers_list

Basis for peering servers. Chains from L</base>.

=head2 servers_root

Display peering servers and peering groups through
F<peering/servers_rules.tt> template. Uses datatables.

=head2 servers_ajax

Get provisioning.voip_peer_hosts from the database and output them as JSON.
The format is meant for parsing with datatables.
Only returns data from the current peering group.

=head2 servers_create

Show a modal to create a new peering server.

=head2 servers_base

Fetch a provisioning.voip_peer_hosts from the database by its id.
Only searches data that belongs to the current peering group.

=head2 servers_edit

Show a modal to edit a peering server.

=head2 servers_delete

Delete a peering server.

=head2 servers_preferences

Not yet implemented.

=head2 rules_list

Basis for peering rules. Chains from L</base>.

=head2 rules_ajax

Get provisioning.voip_peer_rules from the database and output them as JSON.
The format is meant for parsing with datatables.
Only returns data from the current peering group.

=head2 rules_create

Show a modal to create a new peering rule.

=head2 rules_base

Fetch a provisioning.voip_peer_rules from the database by its id.
Only searches data that belongs to the current peering group.

=head2 rules_edit

Show a modal to edit a peering rule.

=head2 rules_delete

Delete a peering rule.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
