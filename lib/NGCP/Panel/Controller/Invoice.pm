package NGCP::Panel::Controller::Invoice;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use DateTime qw();
use DateTime::Format::Strptime;
use HTTP::Status qw(HTTP_SEE_OTHER);
use File::Type;
use MIME::Base64 qw(encode_base64);

use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Message;

use NGCP::Panel::Form::Invoice::Template;
use NGCP::Panel::Form::Invoice::Generate;
use NGCP::Panel::Model::DB::InvoiceTemplate;
use NGCP::Panel::Utils::InvoiceTemplate;

use JSON;
use Number::Phone;

sub auto {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub invoice :Chained('/') :PathPart('invoice') :CaptureArgs(0) {
    my ($self, $c) = @_;
}

sub root :Chained('invoice') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin)
{
    my ($self, $c) = @_;
}

sub messages :Chained('invoice') :PathPart('messages') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('messages');
    $c->stash( messages => $c->flash->{messages} );
    $c->stash( template => 'helpers/ajax_messages.tt' );
    $c->detach( $c->view('SVG') );#no wrapper view
}

sub ajax_datatables_data :Chained('base') :PathPart('ajax') :Args(1) {
    my ($self, $c, $item ) = @_;
    my $dt_columns_json = $c->request->parameters->{dt_columns};
    $c->forward( $item );
    my $dt_columns = from_json($dt_columns_json);
    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{$item.'_ajax'}, $dt_columns );
    $c->detach( $c->view("JSON") );
}

sub base :Chained('invoice') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $reseller_id) = @_;
    $c->log->debug('base');
  
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
    
    my $reseller = $c->model('DB')->resultset('resellers')->search({
        status => { '!=' => 'terminated' },
        id => $reseller_id
    });

    unless($reseller->first) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Reseller not found',
            desc  => $c->loc('Reseller not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }
    $c->stash(
        provider    => $reseller->first,
        provider_rs => $reseller,
        contract    => $reseller->search_rs({ id => $reseller_id })->first->contract 
    );
}


sub invoice_details_zones :Chained('base') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_details_zones');
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $provider_id = $c->stash->{provider}->id;
    my $client_id = $c->stash->{client} ? $c->stash->{client}->id : undef;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    #look, NGCP::Panel::Utils::Contract - it is kind of backend separation here
    #my $form = NGCP::Panel::Form::Invoice::Template->new( );
    my $invoice_details_zones = $backend->get_contract_zonesfees_rs(
        c => $c,
        provider_id => $provider_id,
        client_id => $client_id,
        stime => $stime,
        etime => $etime,
    );
    #TODO: FAKE FAKE FAKE FAKE
    my $invoice_details_zones_ajax = $invoice_details_zones;
    $invoice_details_zones = [$invoice_details_zones_ajax->all()];
    my $i = 1;
    $invoice_details_zones = [map{[$i++,$_]} (@$invoice_details_zones) x 21];
    $c->stash( invoice_details_zones => $invoice_details_zones );
    $c->stash( invoice_details_zones_ajax => $invoice_details_zones_ajax );
}

sub invoice_details_calls :Chained('invoice_details_zones') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_details_calls');
    my $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $provider_id = $c->stash->{provider}->id;
    my $client_id = $c->stash->{client} ? $c->stash->{client}->id : undef;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    #look, NGCP::Panel::Utils::Contract - it is kind of backend separation here
    #my $form = NGCP::Panel::Form::Invoice::Template->new( );
    my $invoice_details_calls = $backend->get_contract_calls_rs(
        c => $c,
        provider_id => $provider_id,
        client_id => $client_id,
        stime => $stime,
        etime => $etime,
    );
    #$invoice_details_calls
    #TODO: FAKE FAKE FAKE FAKE
    my $invoice_details_calls_ajax = $invoice_details_calls;
    #foreach my $call(@$invoice_details_calls_ajax) {
    #    next unless($call->source_cli && $call->source_cli =~ /^\d{5,}$/ && 
    #        $call->destination_user_in && $call->destination_user_in =~ /^\d{5,}$/);
    #    my $s = Number::Phone->new($call->source_cli);
    #    my $d = Number::Phone->new($call->destination_user_in);
    #    next unless($s && $d);
    #}
    
    $invoice_details_calls = [$invoice_details_calls_ajax->all()];
    my $i = 1;
    $invoice_details_calls = [map{[$i++,$_]} (@$invoice_details_calls) x 1];
    $c->stash( invoice_details_calls => $invoice_details_calls );
    $c->stash( invoice_details_calls_ajax => $invoice_details_calls_ajax );
}

sub invoice_list :Chained('base') :PathPart('list') :Args(0) {
    my ($self, $c) = @_;
    my $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    $c->log->debug('invoice_list');
    $c->forward( 'template_list_data' );
    my $provider_id = $c->stash->{provider}->id;
    my $invoice_list = $backend->getProviderInvoiceList(
        provider_id => $provider_id,
    );
    $c->stash( 
        client_contacts_list => $backend->getInvoiceProviderClients( provider_id => $provider_id ),
        invoice_list         => [$invoice_list->all],
        #invoice_list_ajax    => $invoice_list,
        template             => 'invoice/list.tt',
    );
    #$c->detach( $c->view() );
}
sub invoice_list_data :Chained('invoice') :PathPart('list') :Args(0) {
    my ($self, $c) = @_;
    my $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    $c->log->debug('invoice_list_data');
    my $provider_id = $c->stash->{provider}->id;
    my $client_contact_id = $c->request->parameters->{client_contact_id};
    my $invoice_list_ajax = $backend->getProviderInvoiceListAjax(
        provider_id => $provider_id,
        $client_contact_id ? ( client_contact_id => $client_contact_id):(),
    );
    $c->stash( 
        invoice_list_data_ajax    => $invoice_list_ajax,
    );
    #$c->detach( $c->view() );
}

sub provider_client_list :Chained('invoice') :PathPart('clients/list') :Args(0) {
    my ($self, $c) = @_;
    my $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    $c->log->debug('provider_client_list');
    my $provider_id = $c->stash->{provider}->id;
    my $provider_client_list_ajax = $backend->getInvoiceProviderClients(
        provider_id => $provider_id,
    );
    $c->stash( 
        provider_client_list_ajax    => $provider_client_list_ajax,
    );
    #$c->detach( $c->view() );
}

sub invoice_data :Chained('invoice') :PathPart('data') :Args(1) {
    my ($self, $c) = @_;
    my ($invoice_id) = pop;
    $c->log->debug('invoice_data');
    my $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $invoice = $backend->getInvoice(invoice_id => $invoice_id);
    $c->response->content_type('application/pdf');
    $c->response->body( $invoice->first->get_column('data') );
    return;
}

sub invoice_generate :Chained('base') :PathPart('generate') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug($c->action);
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    
    #from parameters
    $in = $c->request->parameters;
    
    my $parser = DateTime::Format::Strptime->new(
        #pattern => '%Y-%m-%d %H:%M',
        pattern => '%Y-%m-%d',
    );
    if($in->{start}) {
        $in->{stime} = $parser->parse_datetime($in->{start});
    }
    if($in->{end}) {
        $in->{etime} = $parser->parse_datetime($in->{end});
    }
    $in->{provider_id} = $c->stash->{provider}->id;
    #$in->{client_contact_id} = $c->request->parameters->{client_contact_id};
    #(undef,undef,@$in{qw/client_contact_id/}) = @_;

    if($in->{invoice_id}){
        #always was sure that i'm calm and even friendly person, but I would kill with pleasure author of dbix.
        my $db_object;
        ($out->{invoice_id},undef,$db_object) = $backend->getInvoiceTemplate( %$in );
        $out->{invoice_data}->{invoice_id} = $db_object->get_column('id');
        $out->{invoice_data}->{provider_id} = $db_object->get_column('reseller_id');
        foreach(qw/name is_active/){$out->{invoice_data}->{$_} = $db_object->get_column($_);}
    }
    if(!$out->{invoice_data}){
        $out->{invoice_data} = $in;
    }
    $validator = NGCP::Panel::Form::Invoice::Generate->new( backend => $backend );
    $validator->remove_undef_in($in);
    #need to think how to automate it - maybe through form showing param through args? what about args for uri_for_action?
    #join('/',$c->controller,$c->action)
    $validator->action( $c->uri_for_action('invoice/invoice_generate',[$in->{provider_id}]) );
    $validator->name( 'invoice_generate' );#from parameters
    #my $posted = 0;
    my $posted = exists $in->{submitid};
    $c->log->debug("posted=$posted;");
    #todo: validate that customer is not terminated and is sip/pbx account
    $validator->process(
        posted => $posted,
        params => $in,
        #item => $in,
        item => $out->{invoice_data},
        #item   => $out->{invoice_data},
    );
    my $in_validated = $validator->fif;
    if($posted){
        if($validator->validated) {
            #copy/pasted from NGCP\Panel\Role\API\Customers.pm 
            my $client_contract  = $backend->getContractInfo('contract_id' => $in->{client_contract_id});
            my $client_contact   = $backend->getContactInfo('contact_id' => $client_contract->contact_id);
            my $provider_contract = $backend->getContractInfo('contract_id' => $c->stash->{provider}->contract_id);
            my $provider_contact = $backend->getContactInfo('contact_id' => $provider_contract->id);
            my $contract_balance = $backend->getContractBalance($in);
            #$c->log->debug("customer->id="..";");
            if(!$contract_balance){
                my $billing_profile = $backend->getBillingProfile($in);
                NGCP::Panel::Utils::Contract::create_contract_balance(
                    c => $c,
                    profile  => $billing_profile,
                    contract => $client_contract,
                    stime    => $in->{stime},
                    etime    => $in->{etime},
                );
                $contract_balance = $backend->getContractBalance($in);
            }
            my $invoice;
            if($contract_balance->invoice_id){
                $invoice = $backend->getInvoice('invoice_id' => $contract_balance->invoice_id);
            }else{
                $invoice = $backend->createInvoice(
                    'contract_balance' => $contract_balance,
                    stime              => $in->{stime},
                    etime              => $in->{etime},
                );
            }
            $c->forward('invoice_details_calls');
            $c->forward('invoice_details_zones');
            #additions for generations
            $in = {
                %$in,
                no_fake_data   => 1,
                tt_type        => 'svg',
                tt_sourcestate => 'saved',
                tt_id          => $c->stash->{provider}->id,
            };
            $out = {
                %$out,
                tt_id          => $c->stash->{provider}->id,
            };
            my $stash = {
                provider => $provider_contact,
                client   => $client_contact,
                invoice  => $invoice,
                invoice_details_zones => $c->stash->{invoice_details_zones},
                invoice_details_calls => $c->stash->{invoice_details_calls},
            };
            my $svg = '';
            $backend->getInvoiceTemplate( %$in, result => \$svg );#provider_id in i is enough
            if(!$svg){
                NGCP::Panel::Utils::InvoiceTemplate::getDefaultInvoiceTemplate( c => $c, type => 'svg', result => \$svg );
                NGCP::Panel::Utils::InvoiceTemplate::preprocessInvoiceTemplateSvg( {no_fake_data => 1}, \$svg);
            }
            $svg = $c->view('SVG')->getTemplateProcessed($c,\$svg, $stash );
            NGCP::Panel::Utils::InvoiceTemplate::convertSvg2Pdf($c,\$svg,$in,$out);
            $backend->storeInvoiceData($invoice,\$out->{tt_string_pdf});
            try {
                #$backend->storeInvoiceTemplateInfo(%$in_validated);
                $c->flash(messages => [{type => 'success', text => $c->loc(
                    $in->{invoice_id}
                    ?'Invoice template updated'
                    :'Invoice template created'
                ) }]);
            } catch($e) {
                NGCP::Panel::Utils::Message->error(
                    c => $c,
                    error => $e,
                    desc  => $c->loc(
                        $in->{invoice_id}
                        ?'Failed to update invoice template.'
                        :'Failed to create invoice template.'
                    ),
                );
            }
            $c->stash( messages => $c->flash->{messages} );
            $c->stash( template => 'helpers/ajax_messages.tt' );
        }else{
            #$c->stash( m        => {create_flag => !$in->{invoice_id}} );
            #$c->stash( form     => $validator );
            ##$c->stash( template => 'helpers/ajax_form_modal.tt' );
            #$c->stash( template => 'invoice/template_info_form.tt' );
            $c->response->headers->header( 'X-Form-Status' => 'error' );
        }
    }
    if(!$validator->validated){
        #$c->stash( in       => $in );
        #$c->stash( out      => $out );
        $c->stash( m        => {create_flag => !$in->{invoice_id}} );
        $c->stash( form     => $validator );
        #$c->stash( template => 'helpers/ajax_form_modal.tt' );
        $c->stash( template => 'invoice/invoice_generate_form.tt' );
    }
    $c->detach( $c->view("SVG") );#to the sake of nowrapper
}



sub template_base :Chained('base') :PathPart('template') :CaptureArgs(0) {
    my ($self, $c) = @_;
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    $c->log->debug('template_base');
    #my $client_id = $c->stash->{client} ? $c->stash->{client}->id : undef ;
    #my $client;
    #if($client_id){
    #    $client = $backend->getClient($client_id);
    #}else{
    #    #$c->stash->{provider}->id;
    #}
    #$c->stash( provider => $c->stash->{reseller}->first );
}

sub template_info :Chained('template_base') :PathPart('info') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug($c->action);
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    
    #from parameters
    $in = $c->request->parameters;
    $in->{provider_id} = $c->stash->{provider}->id;
    #(undef,undef,@$in{qw/tt_id/}) = @_;

    if($in->{tt_id}){
        #always was sure that i'm calm and even friendly person, but I would kill with pleasure author of dbix.
        my $db_object;
        ($out->{tt_id},undef,$db_object) = $backend->getInvoiceTemplate( %$in );
        $out->{tt_data}->{tt_id} = $db_object->get_column('id');
        $out->{tt_data}->{provider_id} = $db_object->get_column('reseller_id');
        foreach(qw/name is_active/){$out->{tt_data}->{$_} = $db_object->get_column($_);}
    }
    if(!$out->{tt_data}){
        $out->{tt_data} = $in;
    }
    $validator = NGCP::Panel::Form::Invoice::Template->new( backend => $backend );
    $validator->remove_undef_in($in);
    #need to think how to automate it - maybe through form showing param through args? what about args for uri_for_action?
    #join('/',$c->controller,$c->action)
    $validator->action( $c->uri_for_action('invoice/template_info',[$in->{provider_id}]) );
    $validator->name( 'template_info' );#from parameters
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
            $c->stash( template => 'invoice/template_info_form.tt' );
            $c->response->headers->header( 'X-Form-Status' => 'error' );
        }
    }else{
        #$c->stash( in       => $in );
        #$c->stash( out      => $out );
        $c->stash( m        => {create_flag => !$in->{tt_id}} );
        $c->stash( form     => $validator );
        #$c->stash( template => 'helpers/ajax_form_modal.tt' );
        $c->stash( template => 'invoice/template_info_form.tt' );
    }
    $c->detach( $c->view("SVG") );#to the sake of nowrapper
}

sub template_activate :Chained('template_base') :PathPart('activate') :Args(2) {
    my ($self, $c) = @_;
    $c->log->debug('template_activate');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id is_active/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{provider_id} = $c->stash->{provider}->id;
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::Invoice::Template->new( backend => $backend );
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
        $backend->activateInvoiceTemplate(%$in);
    }else{
        $backend->deactivateInvoiceTemplate(%$in);
    }
    $c->flash(messages => [{type => 'success', text => $c->loc(
        $in->{is_active}
        ? 'Invoice template deactivated'
        :'Invoice template activated'
    ) }]);
    $c->forward( 'template_list' );
}
sub template_delete :Chained('template_base') :PathPart('delete') :Args(1) {
    my ($self, $c) = @_;
    $c->log->debug('template_delete');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{provider_id} = $c->stash->{provider}->id;
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::Invoice::Template->new( backend => $backend );
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
    
    $backend->deleteInvoiceTemplate(%$in);
    $c->flash(messages => [{type => 'success', text => $c->loc(
        'Invoice template deleted'
    ) }]);
    $c->forward( 'template_list' );
}

sub template_list_data :Chained('base') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_; 
    $c->log->debug('template_list_data');
    my($validator,$backend,$in,$out);
    $in->{provider_id} = $c->stash->{provider}->id;
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $records = [$backend->getInvoiceTemplateList( %$in )->all];
    $c->stash( template_list => $records );
}
sub template_list :Chained('template_base') :PathPart('list') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('template_list');
    $c->forward( 'template_list_data' );
    $c->stash( template => 'invoice/template_list.tt' ); 
    $c->detach($c->view('SVG'));#just no wrapper - maybe there is some other way?
}

sub template :Chained('template_base') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
    $c->forward('invoice_list');
    $c->stash(template => 'invoice/template.tt'); 
}

sub template_view :Chained('template_base') :PathPart('view') :Args {
    my ($self, $c) = @_;
    $c->log->debug('template_view');
    no warnings 'uninitialized';

    my($validator,$backend,$in,$out);

    
    #input
    (undef,undef,@$in{qw/tt_type tt_viewmode tt_sourcestate tt_output_type tt_id/}) = @_ ;
    $in->{provider_id} = $c->stash->{provider}->id;
    #$in->{client_id} = ;
    $in->{tt_string} = $c->request->body_parameters->{template} || '';
    foreach(qw/name is_active/){$in->{$_} = $c->request->parameters->{$_};}
    
    #output
    $out={};

    #storage
    #pass scheme here is ugly, and should be moved somehow to DB::Base
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );

    #input checking & simple preprocessing
    $validator = NGCP::Panel::Form::Invoice::Template->new;
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
        ($out->{tt_id},undef,$out->{tt_data}) = $backend->getInvoiceTemplate( %$in, result => \$tt_string_customer );

        if($out->{tt_data}){
            $out->{json} = {
                tt_data => { 
                    tt_id => $out->{tt_data}->get_column('id'),
                    base64_previewed => ( $out->{tt_data}->get_column('base64_previewed') ? 1 : 0),
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
            #use irka;
            #use Data::Dumper;
            #irka::loglong(Dumper(\%tokens_valid));
            foreach( $tt_string_sanitized=~/$tokens_re/sg ){
                my $token_shape=$_;
                $token_shape=~s/$token_shape_re//sg;
                if(! exists $tokens_valid{$token_shape}){
                    $c->log->debug('Not allowed token in invoice template:'.$_.";\n");
                    $tt_string_sanitized=~s/(?:\[%)+\s*\Q$_\E\s*(?:%\])+//g;
                }
            }
            #/sanitize - to sub, later

            my($tt_stored) = $backend->storeInvoiceTemplateContent( 
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
        #$c->response->content_type('application/json');
        #IE  prompts to save json file.
        $c->response->content_type('text/html');
        #$c->response->content_type('text/javascript');
    }elsif($in->{tt_output_type}=~m'zip'){
        $c->response->content_type('application/zip');
    }
    
    #$out->{tt_string}=~s/(<g .*?(id *=["' ]+(?:title|bg|mid)page["' ]+)?.*?)(?:display="none")(?(2)(?:.*?>)($2.*?>))/$1$3/gs;
    
    if($in->{tt_viewmode} eq 'raw'){
        #$c->stash->{VIEW_NO_TT_PROCESS} = 1;
        $c->response->body($out->{tt_string});
        return;
    }else{#parsed

        my $contacts = $c->model('DB')->resultset('contacts')->search({ id => $in->{provider_id} });
        $c->stash( provider => $contacts->first );

        #some preprocessing should be done only before showing. So, there will be:
        #preShowCustomTemplate prerpocessing
        {
            #preShowInvoice
            #even better - to template filters
            #also to model
            $out->{tt_string_prepared}=$out->{tt_string_stored}=$out->{tt_string};
            NGCP::Panel::Utils::InvoiceTemplate::preprocessInvoiceTemplateSvg($in,\$out->{tt_string_prepared});
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
            #$c->stash( to_json( { aaData => $aaData} ) ); 
            #$c->detach( $c->view('SVG') );#ie doesn't serve correctly json
            $c->response->body( to_json( { aaData => $aaData} ) );
            #$c->detach( $c->view('SVG') );#ie doesn't serve correctly json
        }elsif($in->{tt_output_type} eq 'pdf'){
        #method
            $c->response->content_type('application/pdf');
            my $svg = $c->view('SVG')->getTemplateProcessed($c,\$out->{tt_string_prepared}, $c->stash );
            NGCP::Panel::Utils::InvoiceTemplate::convertSvg2Pdf($c,\$svg,$in,$out);
            $c->response->body($out->{tt_string_pdf});
            return;
            #$out->{tt_string} = `cat $filename `;
        }

    }
}

sub template_aux_embedImage :Chained('invoice') :PathPart('auxembedimage') :Args(0) {
    my ($self, $c) = @_;
    
    #I know somewhere is logging of all visited methods
    $c->log->debug('template_aux_embedImage');
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
    $c->stash(template => 'invoice/template_editor_aux_embedimage.tt');
    $c->detach( $c->view('SVG') );
    
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

I. Peshinskaya,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

# vim: set tabstop=4 expandtab:
