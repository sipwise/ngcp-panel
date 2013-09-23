package NGCP::Panel::Controller::Contact;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Form::Contact::Reseller;
use NGCP::Panel::Form::Contact::Admin;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list_contact :Chained('/') :PathPart('contact') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $contacts = $c->model('DB')->resultset('contacts');
    unless($c->user->is_superuser) {
        $contacts = $contacts->search({ reseller_id => $c->user->reseller_id });
    }
    $c->stash(contacts => $contacts);

    $c->stash(template => 'contact/list.tt');

    $c->stash->{contact_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "reseller.name", search => 1, title => "Reseller" },
        { name => "firstname", search => 1, title => "First Name" },
        { name => "lastname", search => 1, title => "Last Name" },
        { name => "company", search => 1, title => "Company" },
        { name => "email", search => 1, title => "Email" },
    ]);
}

sub root :Chained('list_contact') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list_contact') :PathPart('create') :Args(0) {
    my ($self, $c, $no_reseller) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser && $no_reseller) {
        $form = NGCP::Panel::Form::Contact::Reseller->new;
        $params->{reseller}{id} = $c->user->reseller_id;
        # we'll delete this after validation, as we don't need the reseller in this case
    } elsif($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Contact::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Contact::Reseller->new;
        $params->{reseller}{id} = $c->user->reseller_id;
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            if($c->user->is_superuser && $no_reseller) {
                delete $form->values->{reseller};
            }
            my $contact = $c->stash->{contacts}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->session->{created_objects}->{contact} = { id => $contact->id };
            $c->flash(messages => [{type => 'success', text => 'Contact successfully created'}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create contact.",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub create_without_reseller :Chained('list_contact') :PathPart('create/noreseller') :Args(0) {
    my ($self, $c) = @_;

    $self->create($c, 1); 
}

sub base :Chained('list_contact') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contact_id) = @_;

    unless($contact_id && $contact_id->is_int) {
        $c->flash(messages => [{type => 'error', text => 'Invalid contact id detected'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }
    my $res = $c->stash->{contacts};
    $c->stash(contact => $res->find($contact_id));
    unless($c->stash->{contact}) {
        $c->flash(messages => [{type => 'error', text => 'Contact not found'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c, $no_reseller) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = { $c->stash->{contact}->get_inflated_columns };
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser && $no_reseller) {
        $form = NGCP::Panel::Form::Contact::Reseller->new;
        $params->{reseller}{id} = $c->user->reseller_id;
    } elsif($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Contact::Admin->new;
        $params->{reseller}{id} = $c->stash->{contact}->reseller->id;
    } else {
        $form = NGCP::Panel::Form::Contact::Reseller->new;
    }

    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            if($c->user->is_superuser && $no_reseller) {
                delete $form->values->{reseller};
            } elsif($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
            }
            delete $form->values->{reseller};
            $c->stash->{contact}->update($form->values);
            $c->flash(messages => [{type => 'success', text => 'Contact successfully changed'}]);
            delete $c->session->{created_objects}->{reseller};
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to update contact.",
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
}

sub edit_without_reseller :Chained('base') :PathPart('edit/noreseller') :Args(0) {
    my ($self, $c) = @_;

    $self->edit($c, 1); 
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->stash->{contact}->delete;
        $c->flash(messages => [{type => 'success', text => 'Contact successfully deleted'}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => "Failed to delete contact.",
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/contact'));
}

sub ajax :Chained('list_contact') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    NGCP::Panel::Utils::Datatables::process(
        $c,
        $c->stash->{contacts}->search_rs(undef, {prefetch=>"contracts"}),
        $c->stash->{contact_dt_columns},
        sub {
            my ($result) = @_;
            my %data = (deletable => ($result->contracts->all) ? 0 : 1);
            return %data
        },
    );
    
    $c->detach( $c->view("JSON") );
}

sub ajax_noreseller :Chained('list_contact') :PathPart('ajax_noreseller') :Args(0) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Datatables::process(
        $c,
        $c->stash->{contacts}->search_rs({
            reseller_id => undef,
        }, {prefetch=>"contracts"}),
        $c->stash->{contact_dt_columns},
        sub {
            my ($result) = @_;
            my %data = (deletable => ($result->contracts->all) ? 0 : 1);
            return %data
        },
    );

    $c->detach( $c->view("JSON") );
}

__PACKAGE__->meta->make_immutable;

1;

# vim: set tabstop=4 expandtab:
