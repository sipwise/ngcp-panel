package NGCP::Panel::Controller::Administrator;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Form;
use HTTP::Headers qw();
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Admin;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list_admin :PathPart('administrator') :Chained('/') :CaptureArgs(0) {
    my ($self, $c) = @_;

    my $dispatch_to = '_admin_resultset_' . $c->user->roles;
    $c->stash(
        admins => $self->$dispatch_to($c),
        template => 'administrator/list.tt',
    );
    my $cols = [
        { name => "id", search => 1, title => $c->loc("#") },
    ];
    if($c->user->is_superuser) {
        @{ $cols } =  (@{ $cols }, { name => "reseller.name", search => 1, title => $c->loc("Reseller") });
    }
    @{ $cols } =  (@{ $cols },
        { name => "login", search => 1, title => $c->loc("Login") },
        { name => "is_master", title => $c->loc("Master") },
        { name => "is_active", title => $c->loc("Active") },
        { name => "read_only", title => $c->loc("Read Only") },
        { name => "show_passwords", title => $c->loc("Show Passwords") },
        { name => "call_data", title => $c->loc("Show CDRs") },
        { name => "billing_data", title => $c->loc("Show Billing Info") },
    );
    if($c->user->is_superuser) {
        @{ $cols } =  (@{ $cols },  { name => "lawful_intercept", title => $c->loc("Lawful Intercept") });
    }
    $c->stash->{admin_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, $cols);
    $c->stash->{special_admin_login} = NGCP::Panel::Utils::Admin::get_special_admin_login();
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
    my $params = {};
    $params = merge($params, $c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Reseller", $c);
    }
    $form->process(
        posted => ($c->request->method eq 'POST'),
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
    if ($form->validated) {
        try {
            if($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            } else {
                $form->values->{reseller_id} = $c->user->reseller_id;
            }
            $form->values->{md5pass} = undef;
            $form->values->{saltedpass} = NGCP::Panel::Utils::Admin::generate_salted_hash(delete $form->values->{password});
            $c->stash->{admins}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('Administrator successfully created'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create administrator'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }

    $c->stash(
        create_flag => 1,
        form => $form,
    );
}

sub base :Chained('list_admin') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $administrator_id) = @_;

    $c->detach('/denied_page')
        unless($c->user->is_master);

    unless ($administrator_id && is_int($administrator_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { id => $administrator_id },
            desc  => $c->loc('Invalid administrator id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
    $c->stash(administrator => $c->stash->{admins}->find($administrator_id));
    unless($c->stash->{administrator}) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            desc  => $c->loc('Administrator not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    my $posted = $c->request->method eq 'POST';
    my $form;
    my $params = { $c->stash->{administrator}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = merge($params, $c->session->{created_objects});
    if($c->stash->{administrator}->login eq NGCP::Panel::Utils::Admin::get_special_admin_login()){
       $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::AdminSpecial", $c);
    }elsif($c->user->is_superuser) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Admin", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::Reseller", $c);
    }
    if($form->field('password')){
        $form->field('password')->{required} = 0;
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
    if ($posted && $form->validated) {
        try {
            # don't allow to take away own master rights/write permission, otherwise he'll not be
            # able to manage any more admins
            if($c->stash->{administrator}->id == $c->user->id) {
                delete $form->values->{$_} for qw(is_master is_active read_only);
            }

            if($c->user->is_superuser) {
                $form->values->{reseller_id} = $form->values->{reseller}{id};
                delete $form->values->{reseller};
            }
            delete $form->values->{password} unless length $form->values->{password};
            if(exists $form->values->{password}) {
                $form->values->{md5pass} = undef;
                $form->values->{saltedpass} = NGCP::Panel::Utils::Admin::generate_salted_hash(delete $form->values->{password});
            }
            #should be after other fields, to remove all added values, e.g. reseller_id
            if($c->stash->{administrator}->login eq NGCP::Panel::Utils::Admin::get_special_admin_login()) {
                foreach my $field ($form->fields){
                    if($field ne 'is_active'){
                        delete $form->values->{$field};
                    }
                }
                delete $form->values->{reseller_id};
            }

            $c->stash->{administrator}->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            NGCP::Panel::Utils::Message::info(
                c => $c,
                data => { $c->stash->{administrator}->get_inflated_columns },
                desc => $c->loc('Administrator successfully updated'),
            );
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                data => { $c->stash->{administrator}->get_inflated_columns },
                desc  => $c->loc('Failed to update administrator'),
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
}

sub delete_admin :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    if($c->stash->{administrator}->id == $c->user->id) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { $c->stash->{administrator}->get_inflated_columns },
            desc => $c->loc('Cannot delete myself'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
    my $special_user_login = NGCP::Panel::Utils::Admin::get_special_admin_login();
    if($c->stash->{administrator}->login eq $special_user_login) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { $c->stash->{administrator}->get_inflated_columns },
            desc => $c->loc('Cannot delete "'.$special_user_login.'" administrator. Use "Edit" to disable it.'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }

    if($c->stash->{administrator}->id == $c->user->id) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { $c->stash->{administrator}->get_inflated_columns },
            desc => $c->loc('Cannot delete myself'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
    try {
        $c->stash->{administrator}->delete;
        NGCP::Panel::Utils::Message::info(
            c => $c,
            data => { $c->stash->{administrator}->get_inflated_columns },
            desc => $c->loc('Administrator successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            data => { $c->stash->{administrator}->get_inflated_columns },
            desc => $c->loc('Failed to delete administrator'),
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
}

sub api_key :Chained('base') :PathPart('api_key') :Args(0) {
    my ($self, $c) = @_;

    my $special_user_login = NGCP::Panel::Utils::Admin::get_special_admin_login();
    if($c->stash->{administrator}->login eq $special_user_login) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            data => { $c->stash->{administrator}->get_inflated_columns },
            desc => $c->loc('Cannot change api key of the "'.$special_user_login.'" administrator'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }

    my $serial = $c->stash->{administrator}->ssl_client_m_serial;
    my ($pem, $p12);
    if ($c->req->body_parameters->{'gen.generate'}) {
        my $err;
        my $res = NGCP::Panel::Utils::Admin::generate_client_cert($c, $c->stash->{administrator}, sub {
            my $e = shift;
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                data => { $c->stash->{administrator}->get_inflated_columns },
                desc  => $c->loc("Failed to generate client certificate."),
            );
            $err = 1;
        });
        if($err) {
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
        }

        $serial = $res->{serial};
        my $zipped_file = $res->{file};
        $c->res->headers(HTTP::Headers->new(
            'Content-Type' => 'application/zip',
            'Content-Disposition' => sprintf('attachment; filename=%s', "NGCP-API-client-certificate-$serial.zip")
        ));
        $c->res->body($zipped_file);
        return;
    } elsif ($c->req->body_parameters->{'ca.verify'} || $c->req->parameters->{'ca.verify'}) {
        my $result = $c->model('CA')->check_ca_errors($c);
        if($result){
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $result,
                data => { $c->stash->{administrator}->get_inflated_columns },
                desc  => $c->loc('CA certificate verification failed: '.$result),
            );
        }else{
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc('CA certificate is OK'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    } elsif ($c->req->body_parameters->{'del.delete'}) {
        $c->stash->{administrator}->update({
            ssl_client_m_serial => undef,
            ssl_client_certificate => undef,
        });
        return;
    } elsif ($c->req->body_parameters->{'ca.download'}) {
        my $ca_cert = $c->model('CA')->get_server_cert($c);
        $c->res->headers(HTTP::Headers->new(
            'Content-Type' => 'application/octet-stream',
            'Content-Disposition' => sprintf('attachment; filename=%s', "NGCP-API-ca-certificate.pem")
        ));
        $c->res->body($ca_cert);
        return;
    } elsif ($c->req->body_parameters->{'close'}) {
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
        return;
    }
    my $form;
    if ($serial) {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::APIDownDelete", $c);
    } else {
        $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::APIGenerate", $c);
    }
    $c->stash(
        api_modal_flag => 1,
        form => $form,
    );
}

sub toggle_openvpn :Chained('list_admin') :PathPart('openvpn/toggle') :Args(1) {
    my ($self, $c, $set_active) = @_;

    unless ($set_active eq 'confirm') {
        my ($message, $error) = NGCP::Panel::Utils::Admin::toggle_openvpn($c, $set_active);
        if ( $message ) { 
            NGCP::Panel::Utils::Message::info(
                c => $c,
                desc  => $c->loc($message),
                #modal info screen
                stash => 1,
                flash => 0,
            );
        }
        if ( $error ) { 
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $error,
                desc  => $c->loc($error),
                #modal info screen, we don't need to show error later on some sporadic screen
                stash => 1,
                flash => 0,
            );
        }
    } else {
        $c->stash(
            confirm => 1,
        );
    }
    $c->stash(
        template => 'administrator/openvpn.tt',
    );
    $c->detach( $c->view('TT') );
}

1;

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
