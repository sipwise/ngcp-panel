package NGCP::Panel::Controller::EmailTemplate;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;

use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Email;
use NGCP::Panel::Utils::Message;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);

    $c->stash(template => 'emailtemplate/test.tt');

}

sub tmpl_list :Chained('/') :PathPart('emailtemplate') :CaptureArgs(0) {
    my ( $self, $c ) = @_;

    my $tmpl_rs = $c->model('DB')->resultset('email_templates');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $tmpl_rs = $tmpl_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }

    $c->stash->{tmpl_rs} = $tmpl_rs;
    $c->stash->{template_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'reseller.name', search => 1, title => $c->loc('Reseller') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'from_email', search => 1, title => $c->loc('From') },
        { name => 'subject', search => 1, title => $c->loc('Subject') },
    ]);

    $c->stash->{email_template_external_filter} = $c->session->{email_template_external_filter};

    $c->stash(template => 'emailtemplate/list.tt');
}

sub tmpl_root :Chained('tmpl_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub tmpl_ajax :Chained('tmpl_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->stash->{tmpl_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{template_dt_columns});
    $c->session->{email_template_external_filter} = 'all';
    $c->detach( $c->view("JSON") );
}

sub tmpl_ajax_reseller :Chained('tmpl_list') :PathPart('ajax') :Args(1) {
    my ($self, $c, $reseller_id) = @_;
    my $rs = $c->stash->{tmpl_rs}->search({
        reseller_id => $reseller_id,
    });
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{template_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub tmpl_ajax_default :Chained('tmpl_list') :PathPart('ajax/default') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->model('DB')->resultset('email_templates')->search({
        'me.reseller_id' => undef,
    });
    my $dt_columns = NGCP::Panel::Utils::Datatables::set_columns($c, [
            { name => 'id', search => 1, title => $c->loc('#') },
            { name => 'name', search => 1, title => $c->loc('Name') },
            { name => 'from_email', search => 1, title => $c->loc('From') },
            { name => 'subject', search => 1, title => $c->loc('Subject') },
        ]);
    NGCP::Panel::Utils::Datatables::process($c, $rs, $dt_columns, sub {
            my ($result) = @_;
            my %data = (undeletable => ($c->user->roles eq "admin") ? 0 : 1);
            return %data
        },
    );
    $c->session->{email_template_external_filter} = 'default';
    $c->detach( $c->view("JSON") );
}

sub tmpl_create :Chained('tmpl_list') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $form;
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::EmailTemplate::Admin", $c);
    } elsif($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::EmailTemplate::Reseller", $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    if($posted) {
        $self->create_email_template($c, $form);
    }
    $c->stash(
        form => $form,
        create_flag => 1,
    );
}

sub tmpl_base :Chained('tmpl_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $tmpl_id) = @_;

    $c->detach('/denied_page')
        if($c->user->read_only);

    unless ( $self->check_template_id($c, $tmpl_id) ) {
        return;
    }

    my $rs = $c->stash->{tmpl_rs}->find($tmpl_id);
    unless(defined($rs)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            log => 'Email template does not exist',
            desc => $c->log('Email template does not exist'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }

    $c->stash->{tmpl} = $rs;
}

sub tmpl_delete :Chained('tmpl_base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        foreach(qw/subscriber_email_template_id passreset_email_template_id invoice_email_template_id/){
            $c->model('DB')->resultset('contracts')->search({
                $_ => $c->stash->{tmpl}->id,
            })->update({
                $_ => undef,
            });
        }
        $c->stash->{tmpl}->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $c->stash->{tmpl}->get_inflated_columns },
            desc => $c->loc('Email template successfully deleted'),
        );
    } catch ($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete email template'),
        );
    };
    $c->response->redirect($c->uri_for());
}

sub tmpl_edit :Chained('tmpl_base') :PathPart('edit') {
    my ($self, $c) = @_;
    my ($posted, $form, $params) = $self->prepare_email_template_edit($c);
    if($posted && $form->validated) {
        try {
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
            } elsif($c->user->roles eq "reseller") {
                # don't allow to change reseller id
            }
            delete $form->values->{reseller};
            $c->model('DB')->txn_do(sub {
                $c->stash->{tmpl}->update($form->values);

            });
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Email template successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to update email template'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emailtemplate'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
}

sub tmpl_copy :Chained('tmpl_list') :PathPart('copy'): Args(1) {
    my ($self, $c, $tmpl_id) = @_;

    $c->detach('/denied_page')
        if($c->user->read_only);

    unless ( $self->check_template_id($c, $tmpl_id) ) {
        return;
    }

    my $tmpl = $c->model('DB')->resultset('email_templates')->find($tmpl_id);
    my ($posted, $form, $params) = $self->prepare_email_template_edit($c, $tmpl);
    if($posted) {
        $self->create_email_template($c, $form);
    }
    $c->stash(
        form => $form,
        create_flag => 1,
    );
}

sub check_template_id :Private {
    my ($self, $c, $tmpl_id) = @_;
    unless($tmpl_id && is_int($tmpl_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            log => 'Invalid email template id detected',
            desc => $c->log('Invalid email template id detected'),
        );
        $c->response->redirect($c->uri_for());
        $c->detach;
        return;
    }
    return 1;
}

sub prepare_email_template_edit :Private {
    my ($self, $c, $tmpl) = @_;
    my $posted = ($c->request->method eq 'POST');
    my $form;
    $tmpl //= $c->stash->{tmpl};
    my $params = { $tmpl->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->roles eq "admin") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::EmailTemplate::Admin", $c);
    } elsif($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::EmailTemplate::Reseller", $c);
    }
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {
            'reseller.create' => $c->uri_for('/reseller/create'),
        },
        back_uri => $c->req->uri,
    );
    return $posted, $form, $params;
}
sub create_email_template :Private {
    my ($self, $c, $form) = @_;
    if($form->validated) {
        try {
            if($c->user->roles eq "admin") {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
            } elsif($c->user->roles eq "reseller") {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            delete $form->values->{reseller};

            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $tmpl = $c->stash->{tmpl_rs}->create($form->values);
            });

            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c    => $c,
                desc => $c->loc('Email template successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to create email template'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/emailtemplate'));
    }
}

sub send_test :Chained('tmpl_list') :PathPart('test') :Args(0) {
    my ($self, $c) = @_;

    $c->stash(
        template => 'emailtemplate/test.tt',
        username => 'foobar',
        url => 'http://foo.example.com',
    );

    $c->forward($c->view('TT'));
    my $body = $c->res->body;
    $c->res->body(undef);
    NGCP::Panel::Utils::Email::send_email(
        from => 'noreply@yoursipserver.com',
        to => 'agranig@sipwise.com',
        subject => 'test from catalyst ' . time,
        body => $body,
    );

    $c->res->redirect($c->uri_for('/'));
}

1;
# vim: set tabstop=4 expandtab:
