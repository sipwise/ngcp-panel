package NGCP::Panel::Controller::Reseller;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use DateTime qw();
use HTTP::Status qw(HTTP_SEE_OTHER);
use NGCP::Panel::Form::Reseller;
use NGCP::Panel::Utils::Navigation;
use NGCP::Panel::Utils::Contract;

sub auto :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub list_reseller :Chained('/') :PathPart('reseller') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(
        resellers => $c->model('DB')
            ->resultset('resellers')->search({
                status => { '!=' => 'terminated' }
            }),
        template => 'reseller/list.tt'
    );

    $c->stash->{reseller_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "contract_id", search => 1, title => "Contract #" },
        { name => "name", search => 1, title => "Name" },
        { name => "status", search => 1, title => "Status" },
    ]);

    # we need this in ajax_contracts also
    $c->stash->{contract_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "external_id", search => 1, title => "External #" },
        { name => "contact.email", search => 1, title => "Contact Email" },
        { name => "billing_mappings.billing_profile.name", search => 1, title => "Billing Profile" },
        { name => "status", search => 1, title => "Status" },
    ]);
}

sub root :Chained('list_reseller') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list_reseller') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $resellers = $c->stash->{resellers};
    NGCP::Panel::Utils::Datatables::process($c, $resellers, $c->stash->{reseller_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub create :Chained('list_reseller') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
    	if($c->user->read_only);

    my $params = {};
    $params = $params->merge($c->session->{created_objects});

    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Reseller->new;
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, 
        form => $form, 
        fields => {'contract.create' => $c->uri_for('/contract/create/noreseller') },
        back_uri => $c->req->uri,
    );

    if($form->validated) {
        try {
            $form->params->{contract_id} = delete $form->params->{contract}->{id};
            delete $form->params->{contract};
            my $reseller = $c->model('DB')->resultset('resellers')->create($form->params);
            delete $c->session->{created_objects}->{contract};
            $c->session->{created_objects}->{reseller} = { id => $reseller->id };

            $c->flash(messages => [{type => 'success', text => 'Reseller successfully created'}]);
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Failed to create reseller'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }

    $c->stash(create_flag => 1);
    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
}

sub base :Chained('list_reseller') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $reseller_id) = @_;

    unless($reseller_id && $reseller_id->is_int) {
        $c->flash(messages => [{type => 'error', text => 'Invalid reseller id detected'}]);
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->stash->{contact_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "firstname", search => 1, title => "First Name" },
        { name => "lastname", search => 1, title => "Last Name" },
        { name => "company", search => 1, title => "Company" },
        { name => "email", search => 1, title => "Email" },     
    ]);
    $c->stash->{reseller_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "name", search => 1, title => "Name" },
        { name => "status", search => 1, title => "Status" },
    ]);
    $c->stash->{admin_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "login", search => 1, title => "Name" },
        { name => "is_master", title => "Master" },
        { name => "is_active", title => "Active" },
        { name => "read_only", title => "Read-Only" },
        { name => "show_passwords", title => "Show Passwords" },
        { name => "call_data", title => "Show CDRs" },
    ]);
    $c->stash->{customer_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => "#" },
        { name => "external_id", search => 1, title => "External #" },
        { name => "contact.email", search => 1, title => "Contact Email" },
        { name => "status", search => 1, title => "Status" },
    ]);

    $c->stash(reseller => $c->stash->{resellers}->search_rs({ id => $reseller_id }));
}

sub reseller_contacts :Chained('base') :PathPart('contacts') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{reseller}->first->contract->search_related_rs('contact');
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{contact_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub reseller_contracts :Chained('base') :PathPart('contracts') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{reseller}->first->search_related_rs('contract');
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{contract_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub reseller_single :Chained('base') :PathPart('single') :Args(0) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{reseller}, $c->stash->{reseller_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub reseller_admin :Chained('base') :PathPart('admins') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{reseller}->first->search_related_rs('admins');
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{admin_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub reseller_customers :Chained('base') :PathPart('customers') :Args(0) {
    my ($self, $c) = @_;

    my $rs = $c->model('DB')->resultset('contracts')->search({
        'contact.reseller_id' => $c->stash->{reseller}->first->id
    }, {
        join => 'contact'
    });
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{customer_dt_columns}); 
    $c->detach($c->view('JSON'));
    return;
}

sub edit :Chained('base') :PathPart('edit') :Args(0) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
    	if($c->user->read_only);

    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Reseller->new;

    # we need this in the ajax call to not filter it as used contract
    $c->session->{edit_contract_id} = $c->stash->{reseller}->first->contract_id;

    my $params = { $c->stash->{reseller}->first->get_inflated_columns };
    $params->{contract}{id} = delete $params->{contract_id};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c, form => $form, fields => [qw/contract.create/], 
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            $c->model('DB')->txn_do(sub {
                $form->params->{contract_id} = delete $form->params->{contract}{id};
                delete $form->params->{contract};
                my $old_status = $c->stash->{reseller}->first->status;
                $c->stash->{reseller}->first->update($form->params);

                if($c->stash->{reseller}->first->status ne $old_status) {
                    my $contract = $c->stash->{reseller}->first->contract;
                    $contract->update({ status => $c->stash->{reseller}->first->status });
                    NGCP::Panel::Utils::Contract::recursively_lock_contract(
                        c => $c,
                        contract => $contract,
                    );
                }
            });

            delete $c->session->{created_objects}->{contract};
            delete $c->session->{edit_contract_id};
            $c->flash(messages => [{type => 'success', text => 'Reseller successfully updated'}]);
        } catch($e) {
            $c->log->error($e);
            $c->flash(messages => [{type => 'error', text => 'Failed to update reseller'}]);
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);

    return;
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) {
    my ($self, $c) = @_;

    try {
        $c->model('DB')->txn_do(sub {
            my $reseller = $c->stash->{reseller}->first;
            my $old_status = $reseller->status;
            $reseller->update({ status => 'terminated' });

            if($reseller->status ne $old_status) {
                my $contract = $reseller->contract;
                $contract->update({ status => $reseller->status });
                NGCP::Panel::Utils::Contract::recursively_lock_contract(
                    c => $c,
                    contract => $contract,
                );
            }
        });
        $c->flash(messages => [{type => 'success', text => 'Successfully terminated reseller'}]);
    } catch($e) {
        $c->log->error("failed to terminate reseller: $e");
        $c->flash(messages => [{type => 'error', text => 'Failed to terminate reseller'}]);
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
}

sub details :Chained('base') :PathPart('details') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'reseller/details.tt');
    return;
}

sub ajax_contract :Chained('list_reseller') :PathPart('ajax_contract') :Args(0) {
    my ($self, $c) = @_;
 
    my $edit_contract_id = $c->session->{edit_contract_id};
    my @used_contracts = map { 
        $_->get_column('contract_id') 
            unless($edit_contract_id && $edit_contract_id == $_->get_column('contract_id'))
    } $c->stash->{resellers}->all;
    my $free_contracts = $c->model('DB')
        ->resultset('contracts')
        ->search_rs({
            'me.id' => { 'not in' => \@used_contracts }
        });
    NGCP::Panel::Utils::Datatables::process($c, $free_contracts, $c->stash->{contract_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub create_defaults :Path('create_defaults') :Args(0) {
    my ($self, $c) = @_;
    $c->detach('/denied_page') unless $c->request->method eq 'POST';
    $c->detach('/denied_page')
    	if($c->user->read_only);
    my $now = DateTime->now;
    my %defaults = (
        contacts => {
            firstname => 'Default',
            lastname => 'Contact',
            email => 'default_contact@example.invalid', # RFC 2606
            create_timestamp => $now,
        },
        contracts => {
            status => 'active',
            create_timestamp => $now,
            activate_timestamp => $now,
        },
        resellers => {
            name => 'Default reseller' . sprintf('%04d', rand 10000),
            status => 'active',
        },
        billing_mappings => {
            start_date => $now,
        },
        admins => {
            md5pass => 'defaultresellerpassword',
            is_active => 1,
            show_passwords => 1,
            call_data => 1,
        },
    );
    $defaults{admins}->{login} = $defaults{resellers}->{name} =~ tr/A-Za-z0-9//cdr,

    my $billing = $c->model('DB');
    my %r;
    try {
        $billing->txn_do(sub {
            $r{contacts} = $billing->resultset('contacts')->create({ %{ $defaults{contacts} } });
            $r{contracts} = $billing->resultset('contracts')->create({
                %{ $defaults{contracts} },
                contact_id => $r{contacts}->id,
            });
            $r{resellers} = $billing->resultset('resellers')->create({
                %{ $defaults{resellers} },
                contract_id => $r{contracts}->id,
            });
            $r{billing_mappings} = $billing->resultset('billing_mappings')->create({
                %{ $defaults{billing_mappings} },
                billing_profile_id => 1,
                contract_id => $r{contracts}->id,
                product_id => $billing->resultset('products')->search({ class => 'reseller' })->first->id,
            });
            $r{admins} = $billing->resultset('admins')->create({
                %{ $defaults{admins} },
                reseller_id => $r{resellers}->id,
            });
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $r{billing_mappings}->billing_profile,
                contract => $r{contracts},
            );
        });
    } catch($e) {
        $c->log->error($e);
        $c->flash(messages => [{type => 'error', text => 'Failed to create reseller'}]);
    };
    $c->flash(messages => [{type => 'success', text => "Reseller successfully created with login <b>".$defaults{admins}->{login}."</b> and password <b>".$defaults{admins}->{md5pass}."</b>, please review your settings below" }]);
    $c->res->redirect($c->uri_for_action('/reseller/details', [$r{resellers}->id]));
    $c->detach;
    return;
}

__PACKAGE__->meta->make_immutable;

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Controller::Reseller - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 C<reseller_contacts>

=head2 C<reseller_contracts>

=head2 C<reseller_single>

=head2 C<reseller_admin>

These are Ajax actions called from L</details>, rendering datatables with a single result each.

=head2 C<details>

Renders the F<reseller/details.tt> template, whose datatables relate to and are derived from a reseller id in the
captures.

=head2 C<create_defaults>

Creates a reseller with all dependent contract, contact, billing mapping, admin login in a single step with default
values. Redirects to L</details>.

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

# vim: set tabstop=4 expandtab:
