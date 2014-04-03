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
use NGCP::Panel::Form::InvoiceTemplate::Basic;
use NGCP::Panel::Model::DB::InvoiceTemplate;
use NGCP::Panel::Utils::InvoiceTemplate;

sub auto {
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

    $c->stash(reseller => $c->stash->{resellers}->search_rs({ id => $reseller_id }));
    unless($c->stash->{reseller}->first) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Reseller not found',
            desc  => $c->loc('Reseller not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }
    $c->stash(contract => $c->stash->{resellers}->search_rs({ id => $reseller_id })->first->contract);
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
    #didn't find a way to make it correct with chain
    $c->forward('invoice_details');
    #$self->invoice_details($c);
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
sub messages :Chained('list_reseller') :PathPart('messages') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('messages');
    $c->stash( messages => $c->flash->{messages} );
    $c->stash( template => 'helpers/ajax_messages.tt' );
    $c->detach( $c->view('SVG') );
}
sub invoice_details :Chained('base') :PathPart('invoice') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_details');
    my $contract_id = $c->stash->{contract}->id;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    #look, NGCP::Panel::Utils::Contract - it is kind of backend separation here
    #my $form = NGCP::Panel::Form::InvoiceTemplate::Basic->new( );
    my $invoice_details = NGCP::Panel::Utils::Contract::get_contract_calls_rs(
        c => $c,
        contract_id => $contract_id,
        stime => $stime,
        etime => $etime,
    );
    #TODO: FAKE FAKE FAKE FAKE
    my $invoice_details_raw = $invoice_details;
    $invoice_details = [$invoice_details_raw->all()];
    my $i = 1;
    $invoice_details = [map{[$i++,$_]} (@$invoice_details) x 21];
    $c->stash( invoice_details => $invoice_details );
    $c->stash( invoice_details_raw => $invoice_details_raw );
    #$c->stash( invoice_template_form => $form );
}
sub invoice_details_ajax :Chained('base') :PathPart('invoice/details/ajax') :Args(0) {
    my ($self, $c) = @_;
    my $dt_columns_json = $c->request->parameters->{dt_columns};
    use JSON;
    #use irka;
    #use Data::Dumper;
    #irka::loglong(Dumper($dt_columns));
    $c->forward( 'invoice_details_ajax' );
    my $dt_columns = from_json($dt_columns_json);
    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{invoice_details_raw}, $dt_columns );
    $c->detach( $c->view("JSON") );
}
sub invoice_template_form :Chained('base') :PathPart('invoice/template/form') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug($c->action);
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    
    #from parameters
    $in = $c->request->parameters;
    $in->{contract_id} = $c->stash->{contract}->id;
    #(undef,undef,@$in{qw/tt_id/}) = @_;

    if($in->{tt_id}){
        #always was sure that i'm calm and even friendly person, but I would kill with pleasure author of dbix.
        my $db_object;
        ($out->{tt_id},undef,$db_object) = $backend->getCustomerInvoiceTemplate( %$in );
        $out->{tt_data}->{tt_id} = $db_object->get_column('id');
        $out->{tt_data}->{contract_id} = $db_object->get_column('reseller_id');
        foreach(qw/name is_active/){$out->{tt_data}->{$_} = $db_object->get_column($_);}
    }
    if(!$out->{tt_data}){
        $out->{tt_data} = $in;
    }
    $validator = NGCP::Panel::Form::InvoiceTemplate::Basic->new( backend => $backend );
    $validator->remove_undef_in($in);
    #need to think how to automate it - maybe through form showing param through args? what about args for uri_for_action?
    #join('/',$c->controller,$c->action)
    $validator->action( $c->uri_for_action('reseller/invoice_template_form',[$in->{contract_id}]) );
    $validator->name( 'invoice_template' );#from parameters
    #my $posted = 0;
    my $posted = exists $in->{submitid};
    $c->log->debug("posted=$posted;");
    $validator->process(
        posted => $posted,
        params => $in,
        #item => $in,
        item => $out->{tt_data},
        #item   => $out->{tt_data},
    );
    my $in_validated = $validator->fif;
    if($posted){
        #$c->forward('invoice_template_save');
        if($validator->validated) {
            try {
                $backend->storeInvoiceTemplateInfo(%$in_validated);
                $c->flash(messages => [{type => 'success', text => $c->loc(
                    $in->{tt_id}
                    ?'Invoice template updated'
                    :'Invoice template created'
                ) }]);
            } catch($e) {
                NGCP::Panel::Utils::Message->error(
                    c => $c,
                    error => $e,
                    desc  => $c->loc(
                        $in->{tt_id}
                        ?'Failed to update invoice template.'
                        :'Failed to create invoice template.'
                    ),
                );
            }
            $c->stash( messages => $c->flash->{messages} );
            $c->stash( template => 'helpers/ajax_messages.tt' );
        }else{
            $c->stash( m        => {create_flag => !$in->{tt_id}} );
            $c->stash( form     => $validator );
            #$c->stash( template => 'helpers/ajax_form_modal.tt' );
            $c->stash( template => 'invoice/invoice_template_form_modal.tt' );
            $c->response->headers->header( 'X-Form-Status' => 'error' );
        }
    }else{
        #$c->stash( in       => $in );
        #$c->stash( out      => $out );
        $c->stash( m        => {create_flag => !$in->{tt_id}} );
        $c->stash( form     => $validator );
        #$c->stash( template => 'helpers/ajax_form_modal.tt' );
        $c->stash( template => 'invoice/invoice_template_form_modal.tt' );
    }
    $c->detach( $c->view("SVG") );#to the sake of nowrapper
}


sub invoice_template_activate :Chained('base') :PathPart('invoice_template/activate') :Args(2) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_activate');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id is_active/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{contract_id} = $c->stash->{contract}->id;
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::InvoiceTemplate::Basic->new( backend => $backend );
#    $form->schema( $c->model('DB::InvoiceTemplate')->schema );
    #to common form package ? removing is necessary due to FormHandler param presence evaluation - it is based on key presence, not on defined/not defined value
    #in future this method should be called by ControllerBase
    $validator->remove_undef_in($in);
    
    #really, we don't need a form here at all
    #just use as already implemented fields checking and defaults applying  
    #$validator->setup_form(
    $validator->process(
        posted => 1,
        params => $in,
    );
    #$validator->validate_form();
    
    #multi return...
    $c->log->debug("validated=".$validator->validated.";\n");
    if(!$validator->validated){
        #return;
    }
    my $in_validated = $validator->fif;

    #dirty hack 1
    #really model logic should recieve validated input, but raw input also should be saved somewhere
    $in = $in_validated;
    #think about it more
    if( ! $in->{is_active} ){
        $backend->activateCustomerInvoiceTemplate(%$in);
    }else{
        $backend->deactivateCustomerInvoiceTemplate(%$in);
    }
    $c->flash(messages => [{type => 'success', text => $c->loc(
        $in->{is_active}
        ? 'Invoice template deactivated'
        :'Invoice template activated'
    ) }]);
    $c->forward( 'invoice_template_list' );
}
sub invoice_template_delete :Chained('base') :PathPart('invoice_template/delete') :Args(1) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_delete');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{contract_id} = $c->stash->{contract}->id;
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::InvoiceTemplate::Basic->new( backend => $backend );
#    $form->schema( $c->model('DB::InvoiceTemplate')->schema );
    #to common form package ? removing is necessary due to FormHandler param presence evaluation - it is based on key presence, not on defined/not defined value
    #in future this method should be called by ControllerBase
    $validator->remove_undef_in($in);
    
    #really, we don't need a form here at all
    #just use as already implemented fields checking and defaults applying  
    #$validator->setup_form(
    $validator->process(
        posted => 1,
        params => $in,
    );
    #$validator->validate_form();
    
    #multi return...
    $c->log->debug("validated=".$validator->validated.";\n");
    if(!$validator->validated){
        #return;
    }
    my $in_validated = $validator->fif;

    #dirty hack 1
    #really model logic should recieve validated input, but raw input also should be saved somewhere
    $in = $in_validated;
    #think about it more
    
    $backend->deleteCustomerInvoiceTemplate(%$in);
    $c->flash(messages => [{type => 'success', text => $c->loc(
        'Invoice template deleted'
    ) }]);
    $c->forward( 'invoice_template_list' );
}

sub invoice_template_list_data :Chained('invoice_details') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_; 
    $c->log->debug('invoice_template_list_data');
    my($validator,$backend,$in,$out);
    $in->{contract_id} = $c->stash->{contract}->id;
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $records = $backend->getCustomerInvoiceTemplateList( %$in );
    $c->stash( invoice_template_list => $records );
}
sub invoice_template_list :Chained('base') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_list');
    $c->stash( template => 'invoice/invoice_template_list.tt' ); 
    $c->forward( 'invoice_template_list_data' );
    $c->detach($c->view('SVG'));#just no wrapper - maybe there is some other way?
}

sub invoice :Chained('invoice_template_list_data') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'invoice/invoice.tt'); 
}

sub invoice_template :Chained('invoice_details') :PathPart('template') :Args {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template');
    no warnings 'uninitialized';

    my($validator,$backend,$in,$out);

    #input
    (undef,undef,@$in{qw/tt_type tt_viewmode tt_sourcestate tt_output_type tt_id/}) = @_ ;
    $in->{contract_id} = $c->stash->{contract}->id;
    $in->{tt_string} = $c->request->body_parameters->{template} || '';
    foreach(qw/name is_active/){$in->{$_} = $c->request->parameters->{$_};}
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::InvoiceTemplate::Basic->new;
#    $form->schema( $c->model('DB::InvoiceTemplate')->schema );
    #to common form package ? removing is necessary due to FormHandler param presence evaluation - it is based on key presence, not on defined/not defined value
    $validator->remove_undef_in($in);
    
    #really, we don't need a form here at all
    #just use as already implemented fields checking and defaults applying  
    #$validator->setup_form(
    $validator->process(
        posted => 1,
        params => $in,
    );
    #$validator->validate_form();
    
    #multi return...
    $c->log->debug("validated=".$validator->validated.";\n");
    if(!$validator->validated){
        #return;
    }
    my $in_validated = $validator->fif;

    #dirty hack 1
    #really model logic should recieve validated input, but raw input also should be saved somewhere
    $in = $in_validated;
    
    #model logic
    my $tt_string_default = '';
    my $tt_string_customer = '';
    my $tt_string_force_default = ( $in->{tt_sourcestate} eq 'default' );
    $c->log->debug("force_default=$tt_string_force_default;");
    if(!$in->{tt_string} && !$tt_string_force_default){
        #here we also may be better should contact model, not DB directly. Will return to this separation later
        #at the end - we can figure out rather basic controller behaviour
        ($out->{tt_id},undef,$out->{tt_data}) = $backend->getCustomerInvoiceTemplate( %$in, result => \$tt_string_customer );

        if($out->{tt_data}){
            $out->{json} = {
                tt_data => { 
                    tt_id => $out->{tt_data}->get_column('id'),
                },
            };
            foreach(qw/name is_active/){
                $out->{json}->{tt_data}->{$_} = $out->{tt_data}->get_column($_);
            }
        }
    }
    
    #we need to get default to 1) sanitize (if in->tt_string) or 2)if not in->tt_string and no customer->tt_string
    if($in->{tt_string} || !$tt_string_customer || $tt_string_force_default ){
        try{
            #Utils... mmm - if it were model - there would be no necessity in utils using
            NGCP::Panel::Utils::InvoiceTemplate::getDefaultInvoiceTemplate( c => $c, type => $in->{tt_type}, result => \$tt_string_default );
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => 'default invoice template error',
                desc  => $c->loc('There is no one invoice template in the system.'),
            );
        }
        if($in->{tt_string} && !$tt_string_force_default){
            #sanitize
            my $tt_string_sanitized = $in->{tt_string};
            $tt_string_sanitized =~s/<script.*?\/script>//gs;
            my $tokens_re = qr/\[%(.*?)%\]/;
            my $token_shape_re = qr/\s+/;
            my %tokens_valid = map{$_=~s/$token_shape_re//sg; $_ => 1;} ($tt_string_default=~/$tokens_re/sg);
            foreach( $tt_string_sanitized=~/$tokens_re/sg ){
                my $token_shape=$_;
                $token_shape=~s/$token_shape_re//sg;
                if(! exists $tokens_valid{$token_shape}){
                    $c->log->debug('Not allowed token in invoice template:'.$_.";\n");
                    $tt_string_sanitized=~s/(?:\[%)+\s*\Q$_\E\s*(?:%\])+//g;
                }
            }
            #/sanitize - to sub, later

            my($tt_stored) = $backend->storeCustomerInvoiceTemplate( 
                %$in,
                tt_string_sanitized => \$tt_string_sanitized,
            );
            
            $out->{json} = {
                tt_data => { 
                    tt_id => $tt_stored->{tt_id},
                },
            };

            
            $out->{tt_string} = $tt_string_sanitized;
        }elsif(!$tt_string_customer || $tt_string_force_default){
            $out->{tt_string} = $tt_string_default;
            $c->log->debug("apply default;");
        }
    }else{#we have customer template, we don't have dynamic template string, we weren't requested to show default
        $out->{tt_string} = $tt_string_customer;
    }
    #/model logic
    
    #prepare response
    #mess,mess,mess here
    if($in->{tt_output_type} eq 'svg'){
        $c->response->content_type('text/html');
        #multi-svg document (as well as one-svg documet) is shown ok with text/html
#        $c->response->content_type('image/svg+xml');
    }elsif($in->{tt_output_type} eq 'pdf'){
        $c->response->content_type('application/pdf');
    }elsif($in->{tt_output_type} eq 'html'){
        $c->response->content_type('text/html');
    }elsif($in->{tt_output_type} eq 'json'){
        $c->response->content_type('application/json');
    }elsif($in->{tt_output_type}=~m'zip'){
        $c->response->content_type('application/zip');
    }
    
    if($in->{tt_viewmode} eq 'raw'){
        #$c->stash->{VIEW_NO_TT_PROCESS} = 1;
        $c->response->body($out->{tt_string});
        return;
    }else{#parsed

        my $contacts = $c->model('DB')->resultset('contacts')->search({ id => $in->{contract_id} });
        $c->stash( provider => $contacts->first );

        #some preprocessing should be done only before showing. So, there will be:
        #preShowCustomTemplate prerpocessing
        {
            #preShowInvoice
            #even better - to template filters
            #also to model
            $out->{tt_string_prepared}=$out->{tt_string_stored}=$out->{tt_string};
            $out->{tt_string_prepared}=~s/(?:{\s*)?<!--{|}-->(?:\s*})?//gs;
            $out->{tt_string_prepared}=~s/(<g .*?(id *=["' ]+(?:title|bg|mid)page["' ]+)?.*?)(?:display="none")(?(2)(?:.*?>)($2.*?>))/$1$3/gs;
        }

        if( ($in->{tt_output_type} eq 'svg') || ( $in->{tt_output_type} eq 'html') ){
            #$c->response->content_type('image/svg+xml');
            $c->stash( template => \$out->{tt_string_prepared} ); 
            $c->detach( $c->view('SVG') );
        }elsif($in->{tt_output_type} eq 'json'){
        #method
            $c->log->debug('prepare json');
            
            my $aaData = {
                template =>{
                    raw => $out->{tt_string_stored}, 
                    parsed => $c->view('SVG')->getTemplateProcessed($c, \$out->{tt_string_prepared}, $c->stash ),
                },
            };
            #can be empty if we just load default
            if($out->{json} && $out->{json}->{tt_data}){
                $aaData->{form} = $out->{json}->{tt_data};
            }else{
                #if we didn't have tt_data - then we have empty form fields with applied defaults
                $aaData->{form} = $in;
            }
            $c->stash( aaData => $aaData ); 
            $c->detach( $c->view('JSON') );
        }elsif($in->{tt_output_type} eq 'pdf'){
        #method
            $c->response->content_type('application/pdf');
            my $svg = $c->view('SVG')->getTemplateProcessed($c,\$out->{tt_string_prepared}, $c->stash );
            my(@pages) = $svg=~/(<svg.*?(?:\/svg>))/sig;
            
            #$c->log->debug($svg);
            my ($tempdirbase,$tempdir );
            use File::Temp qw/tempfile tempdir/;
            #my($fh, $tempfilename) = tempfile();
            $tempdirbase = join('/',File::Spec->tmpdir,@$in{qw/contract_id tt_type tt_sourcestate/}, $out->{tt_id});
            use File::Path qw( mkpath );
            ! -e $tempdirbase and mkpath( $tempdirbase, 0, 0777 );
            $tempdir = tempdir( DIR =>  $tempdirbase , CLEANUP => 1 );
            $c->log->debug("tempdirbase=$tempdirbase; tempdir=$tempdir;");
            #try{
            #} catch($e){
            #    NGCP::Panel::Utils::Message->error(
            #        c => $c,
            #        error => "Can't create temporary directory at: $tempdirbase;" ,
            #        desc  => $c->loc("Can't create temporary directory."),
            #    );
            #}
            my $pagenum = 1;
            my @pagefiles;
            foreach my $page (@pages){
                my $fh;
                my $pagefile = "$tempdir/$pagenum.svg";
                push @pagefiles, $pagefile;
                open($fh,">",$pagefile);
                #try{
                #} catch($e){
                #    NGCP::Panel::Utils::Message->error(
                #        c => $c,
                #        error => "Can't create temporary page file at: $tempdirbase/$page.svg;" ,
                #        desc  => $c->loc("Can't create temporary file."),
                #    );
                #}
                print $fh $page;
                close $fh;
                $pagenum++;
            }
            
            my $cmd = "rsvg-convert -f pdf ".join(" ", @pagefiles);
            $c->log->debug($cmd);
            #`chmod ugo+rwx $filename`;
            #binmode(STDOUT);
            #binmode(STDIN);
            #$out->{tt_string} = `$cmd`;
            {
                #$cmd = "fc-list";
                open B, "$cmd |"; 
                binmode B; 
                local $/ = undef; 
                $out->{tt_string_pdf} = <B>;
                close B;
            }
            $c->response->body($out->{tt_string_pdf});
            return;
            #$out->{tt_string} = `cat $filename `;
        }

    }
}

sub invoice_template_aux_embedImage :Chained('list_reseller') :PathPart('auxembedimage') :Args(0) {
    my ($self, $c) = @_;
    
    #I know somewhere is logging of all visited methods
    $c->log->debug('invoice_template_aux_handleImageUpload');
    my($validator,$backend,$in,$out);
    
    #todo
    #mime-type and type checking in form
    
    $in = $c->request->parameters;
    $in->{svg_file} = $c->request->upload('svg_file');
    if($in->{svg_file}) {
        my $ft = File::Type->new();
        $out->{image_content} = $in->{svg_file}->slurp;
        $out->{image_content_mimetype} = $ft->mime_type($out->{image_content});
        $out->{image_content_base64} = encode_base64($out->{image_content}, '');
    }
    $c->log->debug('mime-type '.$out->{image_content_mimetype});
    $c->stash(out => $out);
    $c->stash(in => $in);
    $c->stash(template => 'invoice/invoice_template_aux_embedimage.tt');
    $c->detach( $c->view('SVG') );
    
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
