package NGCP::Panel::Controller::Peering;
use Sipwise::Base;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::PeeringGroup;
use NGCP::Panel::Utils;

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
        return;
    }

    my $res = $c->model('provisioning')->resultset('voip_peer_groups')->find($group_id);
    unless(defined($res)) {
        $c->flash(messages => [{type => 'error', text => 'Peering Group does not exist!'}]);
        $c->response->redirect($c->uri_for());
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
        $c->stash->{group_result}->update($form->custom_get_values);

        $c->flash(messages => [{type => 'success', text => 'Peering Group successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;
    
    return unless (defined $c->stash->{group_result});
    try {
        $c->stash->{group_result}->delete;
        $c->flash(messages => [{type => 'success', text => 'Peering Group successfully deleted!'}]);
    } catch (DBIx::Class::Exception $e) {
        $c->flash(messages => [{type => 'error', text => 'Delete failed.'}]);
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
        $c->model('provisioning')->resultset('voip_peer_groups')->create(
             $formdata );
        $c->flash(messages => [{type => 'success', text => 'Peering group successfully created!'}]);
        $c->response->redirect($c->uri_for_action('/peering/root'));
        return;
    }

    $c->stash(close_target => $c->uri_for_action('/peering/root'));
    $c->stash(create_flag => 1);
    $c->stash(form => $form);
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

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
