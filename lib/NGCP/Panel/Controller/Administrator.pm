package NGCP::Panel::Controller::Administrator;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Administrator qw();
use NGCP::Panel::Utils qw();

sub list_admin :PathPart('administrator') :Chained('/') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->stash(
        admins => $c->model('billing')->resultset('admins'),
        template => 'administrator/list.tt'
    );
    return;
}

sub root :Chained('list_admin') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    return;
}

sub ajax :Chained('list_admin') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $admins = $c->stash->{admins};
    $c->forward(
        '/ajax_process_resultset', [
            $admins,
            [qw(id reseller_id login is_master is_superuser is_active read_only show_passwords call_data lawful_intercept)],
            [ 1 ]
        ]
    );
    $c->detach($c->view('JSON'));
    return;
}

sub create :Chained('list_admin') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    my $form = NGCP::Panel::Form::Administrator->new;
    $form->process(
        posted => $c->request->method eq 'POST',
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    return if NGCP::Panel::Utils::check_form_buttons(
        c => $c,
        form => $form,
        fields => [qw(administrator.create)],
        back_uri => $c->uri_for('create')
    );
    if ($form->validated) {
        try {
            delete $form->params->{save};
            $c->model('billing')->resultset('admins')->create($form->params);
            $c->flash(messages => [{type => 'success', text => 'Administrator created.'}]);
            $c->response->redirect($c->uri_for);
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Creating administrator failed'}]);
            $c->response->redirect($c->uri_for);
        };
        return;
    }
    $c->stash({
        create_flag => 1,
        close_target => $c->uri_for,
        form => $form,
    });
}

sub base :Chained('list_admin') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $administrator_id) = @_;
    unless ($administrator_id && $administrator_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'invalid administrator id'}]);
        $c->response->redirect($c->uri_for);
        return;
    }
    $c->stash(administrator => {$c->stash->{admins}->find($administrator_id)->get_inflated_columns});
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Administrator->new;
    $c->stash->{administrator}->{'reseller.id'} = delete $c->stash->{administrator}->{reseller_id};
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{administrator},
        action => $c->uri_for($c->stash->{administrator}->{id}, 'edit'),
    );
    if ($posted && $form->validated) {
        try {
            my $form_values = $form->value;
            # flatten nested hashref instead of recursive update
            $form_values->{reseller_id} = delete $form_values->{reseller}{id};
            delete $form_values->{reseller};
            $c->stash->{admins}->search_rs({ id => $form_values->{id} })->update($form_values);
            $c->flash(messages => [{type => 'success', text => 'Administrator changed.'}]);
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Updating administrator failed'}]);
        };
        $c->response->redirect($c->uri_for);
    }
    $c->stash({
        close_target => $c->uri_for,
        form => $form,
        edit_flag => 1,
    });
    return;
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    try {
        $c->model('billing')->resultset('admins')->find($c->stash->{administrator}->{id})->delete;
        $c->flash(messages => [{type => 'success', text => 'Administrator deleted.'}]);
    } catch($e) {
        $c->log->error($e);
        $c->flash(messages => [{type => 'error', text => 'Deleting administrator failed'}]);
    };
    $c->response->redirect($c->uri_for);
    return;
}

$CLASS->meta->make_immutable;

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Controller::Administrator - manage platform administrators

=head1 DESCRIPTION

View and edit platform administrators. Administrators have the highest access level and thus can exert the highest
amount of control over resellers and subscribers.

=head1 METHODS

=head2 C<list_admin>

Stashes administrator data structure. Chains off to L</root>.

=head2 C<root>

Display administrators through F<administrator/list.tt> template.

=head2 C<ajax>

JSON emitter for administrator data structure. Implicitly called from F<administrator/list.tt> template.

=head2 C<create>

Show modal dialog form and save administrator details to database.

=head2 C<base>

Capture id of existing administrator. Used for L</edit> and L</delete>.

=head1 AUTHOR

Lars Dieckow C<< <ldieckow@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.
