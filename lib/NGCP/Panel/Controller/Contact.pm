package NGCP::Panel::Controller::Contact;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Contact;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub list_contact :Chained('/') :PathPart('contact') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $contacts;
    if($c->user->auth_realm eq "reseller") {
        $contacts = $c->model('DB')->resultset('contracts')->search({
            reseller_id => $c->user->reseller_id
        })->search_related_rs('contact');
    } else {
        $contacts = $c->model('DB')->resultset('contacts');
    }

    $c->stash(contacts => $contacts);
    $c->stash(template => 'contact/list.tt');

    $c->stash->{contact_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "firstname", search => 1, title => "First Name" },
        { name => "lastname", search => 1, title => "Last Name" },
        { name => "company", search => 1, title => "Company" },
        { name => "email", search => 1, title => "Email" },
    ]);

    # TODO: wtf?
    if($c->session->{redirect_targets} && @{ $c->session->{redirect_targets} }) {
        my $target = ${ $c->session->{redirect_targets} }[0];
        if('/'.$c->request->path eq $target->path) {
            shift @{$c->session->{redirect_targets}};
        } else {
            $c->stash(close_target => $target);
        }
    }
}

sub root :Chained('list_contact') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list_contact') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Contact->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        try {
            delete $form->params->{submitid};
            delete $form->params->{save};
            my $contact = $c->stash->{contacts}->create($form->params);
            if($c->stash->{close_target}) {
                $c->session->{created_object} = { contact => { id => $contact->id } };
                $c->response->redirect($c->stash->{close_target});
                return;
            }
            $c->flash(messages => [{type => 'success', text => 'Contact successfully created'}]);
            $c->response->redirect($c->uri_for_action('/contact/root'));
            return;
        } catch($e) {
            $c->log->error("failed to create contact: $e");
            if($c->stash->{close_target}) {
                $c->response->redirect($c->stash->{close_target});
                return;
            }
            $c->flash(messages => [{type => 'error', text => 'Failed to create contact'}]);
            $c->response->redirect($c->uri_for_action('/contact/root'));
            return;
        }
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub base :Chained('list_contact') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contact_id) = @_;

    unless($contact_id && $contact_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid contact id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(contact => $c->stash->{contacts}->find($contact_id));
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Contact->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $c->stash->{contact},
        action => $c->uri_for($c->stash->{contact}->id, 'edit'),
    );
    if($posted && $form->validated) {
        try {
            delete $form->params->{submitid};
            delete $form->params->{save};
            $c->stash->{contact}->update($form->params);
            $c->flash(messages => [{type => 'success', text => 'Contact successfully changed'}]);
            $c->response->redirect($c->uri_for_action('/contact/root'));
            return;
        } catch($e) {
            $c->log->error("failed to update contact: $e");
            $c->flash(messages => [{type => 'error', text => 'Failed to update contact'}]);
            $c->response->redirect($c->uri_for_action('/contact/root'));
            return;
        }
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{contact}->delete;
    $c->flash(messages => [{type => 'success', text => 'Contact successfully deleted'}]);
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('list_contact') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    #TODO: when user is not logged in, this gets forwarded to login page
    
    my $contacts = $c->model('DB')->resultset('contacts')->search_rs({});
    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{contacts}, $c->stash->{contact_dt_columns});
    
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
