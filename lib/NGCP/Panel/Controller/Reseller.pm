package NGCP::Panel::Controller::Reseller;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use DateTime qw();
use HTTP::Status qw(HTTP_SEE_OTHER);
use File::Type;
use NGCP::Panel::Form::Reseller;
use NGCP::Panel::Form::Reseller::Branding;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::Navigation;

sub auto :Private {
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
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "contract_id", search => 1, title => $c->loc("Contract #") },
        { name => "name", search => 1, title => $c->loc("Name") },
        { name => "status", search => 1, title => $c->loc("Status") },
    ]);

    # we need this in ajax_contracts also
    $c->stash->{contract_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "external_id", search => 1, title => $c->loc("External #") },
        { name => "contact.email", search => 1, title => $c->loc("Contact Email") },
        { name => "billing_mappings.billing_profile.name", search => 1, title => $c->loc("Billing Profile") },
        { name => "status", search => 1, title => $c->loc("Status") },
    ]);
}

sub root :Chained('list_reseller') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
}

sub ajax :Chained('list_reseller') :PathPart('ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    my $resellers = $c->stash->{resellers};
    NGCP::Panel::Utils::Datatables::process($c, $resellers, $c->stash->{reseller_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub create :Chained('list_reseller') :PathPart('create') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
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
        fields => {'contract.create' => $c->uri_for('/contract/reseller/create') },
        back_uri => $c->req->uri,
    );

    if($form->validated) {
        try {
            $form->params->{contract_id} = delete $form->params->{contract}->{id};
            delete $form->params->{contract};
            my $reseller = $c->model('DB')->resultset('resellers')->create($form->params);
            delete $c->session->{created_objects}->{contract};
            $c->session->{created_objects}->{reseller} = { id => $reseller->id };

            $c->flash(messages => [{type => 'success', text => $c->loc('Reseller successfully created') }]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc("Failed to create reseller."),
            );
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
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid reseller id detected',
            desc  => $c->loc('Invalid reseller id detected'),
        );
        $c->response->redirect($c->uri_for());
        return;
    }
    $c->detach('/denied_page')
    	if($c->user->roles eq "reseller" && $c->user->reseller_id != $reseller_id);

    $c->stash->{contact_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "firstname", search => 1, title => $c->loc('First Name') },
        { name => "lastname", search => 1, title => $c->loc('Last Name') },
        { name => "company", search => 1, title => $c->loc('Company') },
        { name => "email", search => 1, title => $c->loc('Email') },     
    ]);
    $c->stash->{reseller_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "name", search => 1, title => $c->loc('Name') },
        { name => "status", search => 1, title => $c->loc('Status') },
    ]);
    $c->stash->{admin_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "login", search => 1, title => $c->loc('Name') },
        { name => "is_master", title => $c->loc('Master') },
        { name => "is_active", title => $c->loc('Active') },
        { name => "read_only", title => $c->loc('Read-Only') },
        { name => "show_passwords", title => $c->loc('Show Passwords') },
        { name => "call_data", title => $c->loc('Show CDRs') },
    ]);
    $c->stash->{customer_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "external_id", search => 1, title => $c->loc('External #') },
        { name => "billing_mappings.product.name", search => 1, title => $c->loc('Product') },
        { name => "contact.email", search => 1, title => $c->loc('Contact Email') },
        { name => "status", search => 1, title => $c->loc('Status') },
    ]);
    $c->stash->{domain_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc('#') },
        { name => "domain", search => 1, title => $c->loc('Domain') },
        { name => "domain_resellers.reseller.name", search => 1, title => $c->loc('Reseller') },
    ]);
    $c->stash->{tmpl_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'name', search => 1, title => $c->loc('Name') },
        { name => 'type', search => 1, title => $c->loc('Type') },
    ]);
    

    $c->stash(reseller => $c->stash->{resellers}->search_rs({ id => $reseller_id }));
    unless($c->stash->{reseller}->first) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Reseller not found',
            desc  => $c->loc('Reseller not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }
    $c->stash->{branding} = $c->stash->{reseller}->first->branding;
}

sub reseller_contacts :Chained('base') :PathPart('contacts/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{reseller}->first->contract->search_related_rs('contact');
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{contact_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub reseller_single :Chained('base') :PathPart('single/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;

    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{reseller}, $c->stash->{reseller_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub reseller_admin :Chained('base') :PathPart('admins/ajax') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{reseller}->first->search_related_rs('admins');
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{admin_dt_columns});
    $c->detach($c->view('JSON'));
    return;
}

sub edit :Chained('base') :PathPart('edit') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->read_only);

    my $reseller = $c->stash->{reseller}->first;

    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Reseller->new;

    # we need this in the ajax call to not filter it as used contract
    $c->session->{edit_contract_id} = $reseller->contract_id;

    my $params = { $reseller->get_inflated_columns };
    $params->{contract}{id} = delete $params->{contract_id};
    $params = $params->merge($c->session->{created_objects});
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {'contract.create' => $c->uri_for('/contract/reseller/create') },
        back_uri => $c->req->uri,
    );

    if($posted && $form->validated) {
        try {
            $c->model('DB')->txn_do(sub {
                $form->params->{contract_id} = delete $form->params->{contract}{id};
                delete $form->params->{contract};
                my $old_status = $reseller->status;
                $reseller->update($form->params);

                if($reseller->status ne $old_status) {
                    $self->_handle_reseller_status_change($c, $reseller);
                }
            });

            delete $c->session->{created_objects}->{contract};
            delete $c->session->{edit_contract_id};
            $c->flash(messages => [{type => 'success', text => $c->loc('Reseller successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update reseller.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(form => $form);
    $c->stash(edit_flag => 1);

    return;
}

sub terminate :Chained('base') :PathPart('terminate') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;

    my $reseller = $c->stash->{reseller}->first;

    if ($reseller->id == 1) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Cannot terminate reseller with the id 1',
            desc  => $c->loc('Cannot terminate reseller with the id 1'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }

    try {
        $c->model('DB')->txn_do(sub {
            my $old_status = $reseller->status;
            $reseller->update({ status => 'terminated' });

            if($reseller->status ne $old_status) {
                $self->_handle_reseller_status_change($c,$reseller);
            }
        });
        $c->flash(messages => [{type => 'success', text => $c->loc('Successfully terminated reseller')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to terminate reseller.'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
}

sub _handle_reseller_status_change {
    my ($self, $c, $reseller) = @_;
    
    my $contract = $reseller->contract;
    $contract->update({ status => $reseller->status });
    NGCP::Panel::Utils::Contract::recursively_lock_contract(
        c => $c,
        contract => $contract,
    );
    
    if($reseller->status eq "terminated") {
        #delete ncos_levels
        $reseller->ncos_levels->delete_all;
        #delete voip_number_block_resellers
        $reseller->voip_number_block_resellers->delete_all;
        #delete voip_sound_sets
        $reseller->voip_sound_sets->delete_all;
        #delete voip_rewrite_rule_sets
        $reseller->voip_rewrite_rule_sets->delete_all;
        #delete autoprov_devices
        $reseller->autoprov_devices->delete_all;
    }
}

sub details :Chained('base') :PathPart('details') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;

    $c->stash(template => 'reseller/details.tt');
    return;
}

sub ajax_contract :Chained('list_reseller') :PathPart('ajax_contract') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
 
    my $edit_contract_id = $c->session->{edit_contract_id};
    my @used_contracts = map {
        unless($edit_contract_id && $edit_contract_id == $_->get_column('contract_id')) {
            $_->get_column('contract_id')
        } else {}
    } $c->stash->{resellers}->all;
    my $free_contracts = NGCP::Panel::Utils::Contract::get_contract_rs(
            schema => $c->model('DB'))
        ->search_rs({
            'me.status' => { '!=' => 'terminated' },
            'me.id' => { 'not in' => \@used_contracts },
            'product.class' => 'reseller',
        },{
            join => { 'billing_mappings' => 'product'},
        }
        );
    NGCP::Panel::Utils::Datatables::process($c, $free_contracts, $c->stash->{contract_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub create_defaults :Path('create_defaults') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) {
    my ($self, $c) = @_;
    $c->detach('/denied_page') unless $c->request->method eq 'POST';
    $c->detach('/denied_page')
    	if($c->user->read_only);
    my $now = NGCP::Panel::Utils::DateTime::current_local;
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
        NGCP::Panel::Utils::Message->error(
            c => $c,
            error => $e,
            desc  => "Failed to create reseller.",
        );
    };
    $c->flash(messages => [{type => 'success', text => 
            $c->loc("Reseller successfully created with login <b>[_1]</b> and password <b>[_2]</b>, please review your settings below",
                $defaults{admins}->{login},$defaults{admins}->{md5pass}) }]);
    $c->res->redirect($c->uri_for_action('/reseller/details', [$r{resellers}->id]));
    $c->detach;
    return;
}

sub css :Chained('base') :PathPart('css') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;
    $c->stash(template => 'reseller/branding.tt');
    return;
}

sub edit_branding_css :Chained('base') :PathPart('css/edit') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    $c->detach('/denied_page')
        if($c->user->read_only);
    my $back;
    if($c->user->roles eq "admin") {
        $c->stash(template => 'reseller/details.tt');
        $back = $c->uri_for_action('/reseller/details', $c->req->captures);
    } else {
        $c->stash(template => 'reseller/branding.tt');
        $back = $c->uri_for_action('/reseller/css', $c->req->captures);
    }

    my $reseller = $c->stash->{reseller}->first;
    my $branding = $reseller->branding;

    my $posted = $c->request->method eq 'POST';
    my $form = NGCP::Panel::Form::Reseller::Branding->new;

    if($posted) {
        $c->req->params->{logo} = $c->req->upload('logo');
    }

    my $params = $branding ? { $branding->get_inflated_columns } : {};
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => {},
        back_uri => $back,
    );

    if($posted && $form->validated) {
        try {
            $c->model('DB')->txn_do(sub {
                if($c->user->roles eq "admin") {
                    $form->params->{reseller_id} = $reseller->id;
                } elsif($c->user->roles eq "reseller") {
                    $form->params->{reseller_id} = $c->user->reseller_id;
                }
                delete $form->params->{reseller};
                delete $form->params->{back};

                my $ft = File::Type->new();
                if($form->params->{logo}) {
                    my $logo = delete $form->params->{logo};
                    $form->params->{logo} = $logo->slurp;
                    $form->params->{logo_image_type} = $ft->mime_type($form->params->{logo});
                } else {
                    delete $form->params->{logo};
                }

                unless(defined $branding) {
                    $c->model('DB')->resultset('reseller_brandings')->create($form->params);
                } else {
                    $branding->update($form->params);
                }
            });

            $c->flash(messages => [{type => 'success', text => $c->loc('Reseller branding successfully updated')}]);
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to update reseller branding'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $back);
    }

    $c->stash(close_target => $c->uri_for());
    $c->stash(branding_form => $form);
    $c->stash(branding_edit_flag => 1);
    $c->stash(close_target => $back);

    return;
}

sub get_branding_logo :Chained('base') :PathPart('css/logo/download') :Args(0) {
    my ($self, $c) = @_;


    my $reseller = $c->stash->{reseller}->first;
    my $branding = $reseller->branding;

    unless($branding || $branding->logo) {
        $c->response->body($c->loc('404 - No branding logo available for this reseller'));
        $c->response->status(404);
        return;
    }
    $c->response->content_type($branding->logo_image_type);
    $c->response->body($branding->logo);
}

sub delete_branding_logo :Chained('base') :PathPart('css/logo/delete') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $back;
    if($c->user->roles eq "admin") {
        $back = $c->uri_for_action('/reseller/details', $c->req->captures);
    } else {
        $back = $c->uri_for_action('/reseller/css', $c->req->captures);
    }

    my $reseller = $c->stash->{reseller}->first;
    my $branding = $reseller->branding;

    if($branding) {
        $branding->update({ logo => undef, logo_image_type => undef });
    }

    $c->response->redirect($back);
}

sub get_branding_css :Chained('base') :PathPart('css/download') :Args(0) {
    my ($self, $c) = @_;


    my $reseller = $c->stash->{reseller}->first;
    my $branding = $reseller->branding;

    unless($branding || $branding->css) {
        $c->response->body($c->loc('404 - No branding css available for this reseller'));
        $c->response->status(404);
        return;
    }
    $c->response->content_type('text/css');
    $c->response->body($branding->css);
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
