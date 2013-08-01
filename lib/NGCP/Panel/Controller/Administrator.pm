package NGCP::Panel::Controller::Administrator;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Administrator::Reseller;
use NGCP::Panel::Form::Administrator::Admin;
use NGCP::Panel::Utils::Navigation;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list_admin :PathPart('administrator') :Chained('/') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dispatch_to = '_admin_resultset_' . $c->user->auth_realm;
    $c->stash(
        admins => $self->$dispatch_to($c),
        template => 'administrator/list.tt',
    );
    my $cols = [
        { name => "id", search => 1, title => "#" },
    ];
    if($c->user->is_superuser) {
        @{ $cols } =  (@{ $cols }, { name => "reseller.name", search => 1, title => "Reseller" });
    }
    @{ $cols } =  (@{ $cols }, 
        { name => "login", search => 1, title => "Login" },
        { name => "is_master", title => "Master" },
        { name => "is_active", title => "Active" },
        { name => "read_only", title => "Read Only" },
        { name => "show_passwords", title => "Show Passwords" },
        { name => "call_data", title => "Show CDRs" },
    );
    if($c->user->is_superuser) {
        @{ $cols } =  (@{ $cols },  { name => "lawful_intercept", title => "Lawful Intercept" });
    }
    $c->stash->{admin_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $cols);
    return;
}

sub _admin_resultset_admin {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('admins');
}

sub _admin_resultset_reseller {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('admins')->search({
        reseller_id => $c->user->reseller_id,
    });
}

sub root :Chained('list_admin') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    return;
}

sub ajax :Chained('list_admin') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $admins = $c->stash->{admins};
    NGCP::Panel::Utils::Datatables::process($c, $admins, $c->stash->{admin_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub create :Chained('list_admin') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
    	unless($c->user->is_master);

    my $form;
    if($c->user->auth_realm eq "admin") {
        $form = NGCP::Panel::Form::Administrator::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Administrator::Reseller->new;
        $c->request->params->{reseller}{id} = $c->user->reseller_id,
    }
    $form->process(
        posted => $c->request->method eq 'POST',
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => [qw(administrator.create)],
        back_uri => $c->req->uri,
    );
    if ($form->validated) {
        try {
            $form->params->{reseller_id} = delete $form->params->{reseller}{id};
            delete $form->params->{reseller};
            delete $form->params->{id};
            $c->model('DB')->resultset('admins')->create($form->params);
            $c->flash(messages => [{type => 'success', text => 'Administrator created.'}]);
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Creating administrator failed'}]);
        }
        $c->response->redirect($c->uri_for);
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

    $c->detach('/denied_page')
    	unless($c->user->is_master);

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
    my $form;
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Administrator::Admin->new;
        $c->stash->{administrator}->{reseller}{id} = 
            delete $c->stash->{administrator}->{reseller_id};
    } else {
        $form = NGCP::Panel::Form::Administrator::Reseller->new;
    }
    $form->field('md5pass')->{required} = 0;

    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{administrator},
        action => $c->uri_for($c->stash->{administrator}->{id}, 'edit'),
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $c->req->uri,
    );
    if ($posted && $form->validated) {
        try {
            my $form_values = $form->value;

            # don't allow to take away own master rights, otherwise he'll not be
            # able to manage any more admins
            if($form_values->{id} == $c->user->id) {
                delete $form_values->{is_master};
                delete $form_values->{is_active};
            }

            # flatten nested hashref instead of recursive update
            $form_values->{reseller_id} = delete $form_values->{reseller}{id}
                if($form_values->{reseller}{id});
            delete $form_values->{reseller};
            delete $form_values->{md5pass} unless length $form_values->{md5pass};
            $c->stash->{admins}->search_rs({ id => $form_values->{id} })->update_all($form_values);
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
        $c->model('DB')->resultset('admins')->find($c->stash->{administrator}->{id})->delete;
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

# vim: set tabstop=4 expandtab:
