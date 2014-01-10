package NGCP::Panel::Controller::Administrator;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use HTTP::Headers qw();
use NGCP::Panel::Form::Administrator::Reseller;
use NGCP::Panel::Form::Administrator::Admin;
use NGCP::Panel::Form::Administrator::APIGenerate qw();
use NGCP::Panel::Form::Administrator::APIDownDelete qw();
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

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
    my $params = {};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Administrator::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Administrator::Reseller->new;
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
            $c->stash->{admins}->create($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->flash(messages => [{type => 'success', text => 'Administrator successfully created'}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to create administrator.",
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

    unless ($administrator_id && $administrator_id->is_integer) {
        $c->flash(messages => [{type => 'error', text => 'Invalid administrator id detected'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
    $c->stash(administrator => $c->stash->{admins}->find($administrator_id));
    unless($c->stash->{administrator}) {
        $c->flash(messages => [{type => 'error', text => 'Administrator not found'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;
    my $posted = $c->request->method eq 'POST';
    my $form;
    my $params = { $c->stash->{administrator}->get_inflated_columns };
    $params->{reseller}{id} = delete $params->{reseller_id};
    $params = $params->merge($c->session->{created_objects});
    if($c->user->is_superuser) {
        $form = NGCP::Panel::Form::Administrator::Admin->new;
    } else {
        $form = NGCP::Panel::Form::Administrator::Reseller->new;
    }
    $form->field('md5pass')->{required} = 0;

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
            delete $form->values->{md5pass} unless length $form->values->{md5pass};
            $c->stash->{administrator}->update($form->values);
            delete $c->session->{created_objects}->{reseller};
            $c->flash(messages => [{type => 'success', text => 'Administrator successfully updated'}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => "Failed to update administrator.",
            );
        };
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }

    $c->stash(
        form => $form,
        edit_flag => 1,
    );
}

sub delete :Chained('base') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;

    if($c->stash->{administrator}->id == $c->user->id) {
        $c->flash(messages => [{type => 'error', text => 'Cannot delete myself'}]);
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
    }
    try {
        $c->stash->{administrator}->delete;
        $c->flash(messages => [{type => 'success', text => 'Administrator successfully deleted'}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => "Failed to delete administrator.",
        );
    };
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/administrator'));
}

sub api_key :Chained('base') :PathPart('api_key') :Args(0) {
    my ($self, $c) = @_;
    my $serial = $c->stash->{administrator}->ssl_client_m_serial;
    my $cert;
    if ($c->req->body_parameters->{'gen.generate'}) {
        $serial = time;
        $cert = $c->model('CA')->make_client($c, $serial);
        my $updated;
        while (!$updated) {
            try {
                $c->stash->{administrator}->update({ 
                    ssl_client_m_serial => $serial,
                    ssl_client_certificate => $cert,
                });
                $updated = 1;
            } catch(DBIx::Class::Exception $e where { "$_" =~ qr'Duplicate entry' }) {
                $serial++;
            };
        }
    } elsif ($c->req->body_parameters->{'del.delete'}) {
        undef $serial;
        undef $cert;
        $c->stash->{administrator}->update({ 
            ssl_client_m_serial => $serial,
            ssl_client_certificate => $cert,
        });
    } elsif ($c->req->body_parameters->{'pem.download'}) {
        $cert = $c->stash->{administrator}->ssl_client_certificate;
        $serial = $c->stash->{administrator}->ssl_client_m_serial; 
        $c->res->headers(HTTP::Headers->new(
            'Content-Type' => 'application/octet-stream',
            'Content-Disposition' => sprintf('attachment; filename=%s', "NGCP-API-client-certificate-$serial.pem")
        ));
        $c->res->body($cert);
        return;
    } elsif ($c->req->body_parameters->{'p12.download'}) {
        $cert = $c->stash->{administrator}->ssl_client_certificate;
        $serial = $c->stash->{administrator}->ssl_client_m_serial;
        my $p12 = $c->model('CA')->make_pkcs12($c, $serial, $cert, 'sipwise');
        $c->res->headers(HTTP::Headers->new(
            'Content-Type' => 'application/octet-stream',
            'Content-Disposition' => sprintf('attachment; filename=%s', "NGCP-API-client-certificate-$serial.p12")
        ));
        $c->res->body($p12);
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
        $form = NGCP::Panel::Form::Administrator::APIDownDelete->new;
    } else {
        $form = NGCP::Panel::Form::Administrator::APIGenerate->new;
    }
    $c->stash(
        api_modal_flag => 1,
        form => $form,
    );
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
