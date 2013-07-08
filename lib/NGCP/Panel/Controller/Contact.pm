package NGCP::Panel::Controller::Contact;
use Moose;
use namespace::autoclean;
BEGIN { extends 'Catalyst::Controller'; }
use NGCP::Panel::Form::Contact;

=head1 NAME

NGCP::Panel::Controller::Contact - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    return 1;
}

sub list :Chained('/') :PathPart('contact') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $contacts = [
        {id => 1, firstname => 'Foo1', lastname => '1Bar', email => 'foo1@example.org' },
        {id => 2, firstname => 'Foo2', lastname => '2Bar', email => 'foo2@example.org' },
        {id => 3, firstname => 'Foo3', lastname => '3Bar', email => 'foo3@example.org' },
        {id => 4, firstname => 'Foo4', lastname => '4Bar', email => 'foo4@example.org' },
    ];
    $c->stash(contacts => $contacts);
    $c->stash(template => 'contact/list.tt');

    if($c->session->{redirect_targets} && @{ $c->session->{redirect_targets} }) {
        my $target = ${ $c->session->{redirect_targets} }[0];
        if('/'.$c->request->path eq $target->path) {
            shift @{$c->session->{redirect_targets}};
        } else {
            $c->stash(close_target => $target);
        }
    }
}

sub root :Chained('list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub create :Chained('list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $form = NGCP::Panel::Form::Contact->new;
    $form->process(
        posted => ($c->request->method eq 'POST'),
        params => $c->request->params,
        action => $c->uri_for('create'),
    );
    if($form->validated) {
        if($c->stash->{close_target}) {
            $c->response->redirect($c->stash->{close_target});
            return;
        }
        $c->flash(messages => [{type => 'success', text => 'Contact successfully created!'}]);
        $c->response->redirect($c->stash->{close_target});
        return;
    }

    $c->stash(create_flag => 1);
    $c->stash(form => $form);
}

sub search :Chained('list') :PathPart('search') Args(0) {
    my ($self, $c) = @_;

    $c->flash(messages => [{type => 'info', text => 'Contact search not implemented!'}]);
    $c->response->redirect($c->uri_for());
}

sub base :Chained('/contact/list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $contact_id) = @_;

    unless($contact_id && $contact_id =~ /^\d+$/) {
        $c->flash(messages => [{type => 'error', text => 'Invalid contact id detected!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    # TODO: fetch details of contact from model
    my @rfilter = grep { $_->{id} == $contact_id } @{ $c->stash->{contacts} };
    $c->stash(contact =>  shift @rfilter);
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form = NGCP::Panel::Form::Contact->new;
    $form->process(
        posted => 1,
        params => $posted ? $c->request->params : $c->stash->{contact},
        action => $c->uri_for($c->stash->{contact}->{id}, 'edit'),
    );
    if($posted && $form->validated) {
        $c->flash(messages => [{type => 'success', text => 'Contact successfully changed!'}]);
        $c->response->redirect($c->uri_for());
        return;
    }

    $c->stash(form => $form);
    $c->stash(edit_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    # $c->model('Provisioning')->contact($c->stash->{contact}->{id})->delete;
    $c->flash(messages => [{type => 'info', text => 'Contact delete not implemented!'}]);
    $c->response->redirect($c->uri_for());
}

sub ajax :Chained('list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    
    #TODO: when user is not logged in, this gets forwarded to login page
    
    my $contacts = $c->model('DB')->resultset('contacts')->search_rs({});
    
    $c->forward( "/ajax_process_resultset", [$contacts,
                 ["id", "firstname", "lastname", "email"],
                 ["firstname", "lastname", "email"]]);
    
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
