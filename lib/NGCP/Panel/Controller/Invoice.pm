package NGCP::Panel::Controller::Invoice;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }
use DateTime qw();
use HTTP::Status qw(HTTP_SEE_OTHER);
use File::Type;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Message;

use NGCP::Panel::Form::InvoiceTemplate::Basic;
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

sub list_invoice_template :Chained('/') :PathPart('invoice') :CaptureArgs(0) {
    my ($self, $c) = @_;

    $c->stash(
        resellers => $c->model('DB')
            ->resultset('resellers')->search({
                status => { '!=' => 'terminated' }
            }),
        template => 'invoice/invoice.tt'
    );
}

sub root :Chained('list_invoice_template') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin)
{
    my ($self, $c) = @_;
}

sub messages :Chained('list_invoice_template') :PathPart('messages') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('messages');
    $c->stash( messages => $c->flash->{messages} );
    $c->stash( template => 'helpers/ajax_messages.tt' );
    $c->detach( $c->view('SVG') );#no wrapper view
}

sub ajax_allmighty :Chained('base') :PathPart('ajaxall') :Args(1) {
    my ($self, $c, $item ) = @_;
    my $dt_columns_json = $c->request->parameters->{dt_columns};
    $c->forward( $item );
    my $dt_columns = from_json($dt_columns_json);
    NGCP::Panel::Utils::Datatables::process($c, $c->stash->{$item.'_ajax'}, $dt_columns );
    $c->detach( $c->view("JSON") );
}

sub base :Chained('list_invoice_template') :PathPart('') :CaptureArgs(1) {
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

    $c->stash(reseller => $c->stash->{resellers}->search_rs({ id => $reseller_id }));
    unless($c->stash->{reseller}->first) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Reseller not found',
            desc  => $c->loc('Reseller not found'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/reseller'));
    }
    $c->stash(contract => $c->stash->{resellers}->search_rs({ id => $reseller_id })->first->contract );
    $c->stash(provider => $c->stash->{resellers}->first );
}
sub details :Chained('base') :PathPart('') :Args(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin)
{
    my ($self, $c) = @_;
    $c->forward('invoice_details_zones');
    $c->forward('invoice_details_calls');
    $c->forward('invoice_template_list_data');
    #$self->invoice_details_zones($c);
    #$self->invoice_details_calles($c);
}

sub invoice_base :Chained('base') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    $c->log->debug('invoice_base');
    my $client_id = $c->stash->{client} ? $c->stash->{client}->id : undef ;
    my $client;
    if($client_id){
        $client = $backend->getClient($client_id);
    }else{
        #$c->stash->{provider}->id;
    }
    $c->stash( provider => $c->stash->{reseller}->first );
}

sub invoice_details_zones :Chained('invoice_base') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_details_zones');
    $c->forward( 'invoice_base' );
    my $contract_id = $c->stash->{provider}->id;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    #look, NGCP::Panel::Utils::Contract - it is kind of backend separation here
    #my $form = NGCP::Panel::Form::InvoiceTemplate::Basic->new( );
    my $invoice_details_zones = NGCP::Panel::Utils::Contract::get_contract_zonesfees_rs(
        c => $c,
        contract_id => $contract_id,
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
    $c->forward( 'invoice_base' );
    my $contract_id = $c->stash->{provider}->id;
    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    #look, NGCP::Panel::Utils::Contract - it is kind of backend separation here
    #my $form = NGCP::Panel::Form::InvoiceTemplate::Basic->new( );
    my $invoice_details_calls = NGCP::Panel::Utils::Contract::get_contract_calls_rs(
        c => $c,
        contract_id => $contract_id,
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
sub invoice_template_info :Chained('invoice_base') :PathPart('invoice/template/info') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug($c->action);
    my($validator,$backend,$in,$out);
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    
    #from parameters
    $in = $c->request->parameters;
    $in->{contract_id} = $c->stash->{provider}->id;
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
    $validator->action( $c->uri_for_action('invoice/invoice_template_info',[$in->{contract_id}]) );
    $validator->name( 'invoice_template_info' );#from parameters
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
            $c->stash( template => 'invoice/invoice_template_info_form.tt' );
            $c->response->headers->header( 'X-Form-Status' => 'error' );
        }
    }else{
        #$c->stash( in       => $in );
        #$c->stash( out      => $out );
        $c->stash( m        => {create_flag => !$in->{tt_id}} );
        $c->stash( form     => $validator );
        #$c->stash( template => 'helpers/ajax_form_modal.tt' );
        $c->stash( template => 'invoice/invoice_template_info_form.tt' );
    }
    $c->detach( $c->view("SVG") );#to the sake of nowrapper
}


sub invoice_template_activate :Chained('invoice_base') :PathPart('invoice/template/activate') :Args(2) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_activate');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id is_active/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{contract_id} = $c->stash->{provider}->id;
    
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
sub invoice_template_delete :Chained('invoice_base') :PathPart('invoice/template/delete') :Args(1) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_delete');
    my($validator,$backend,$in,$out);

    (undef,undef,@$in{qw/tt_id/}) = @_;
    #check that this id really belongs to specified contract? or just add contract condition to delete query?
    #checking is more universal
    #this is just copy-paste from method above
    #of course we are chained and we can put in and out to stash
    #input
    $in->{contract_id} = $c->stash->{provider}->id;
    
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

sub invoice_template_list_data :Chained('invoice_details_calls') :PathPart('') :CaptureArgs(0) {
    my ($self, $c) = @_; 
    $c->log->debug('invoice_template_list_data');
    my($validator,$backend,$in,$out);
    $in->{contract_id} = $c->stash->{provider}->id;
    $backend = NGCP::Panel::Model::DB::InvoiceTemplate->new( schema => $c->model('DB') );
    my $records = $backend->getCustomerInvoiceTemplateList( %$in );
    $c->stash( invoice_template_list => $records );
}
sub invoice_template_list :Chained('invoice_base') :PathPart('invoice/template') :Args(0) {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template_list');
    $c->stash( template => 'invoice/invoice_template_list.tt' ); 
    $c->forward( 'invoice_template_list_data' );
    $c->detach($c->view('SVG'));#just no wrapper - maybe there is some other way?
}

sub invoice :Chained('invoice_template_list_data') :PathPart('invoice') :Args(0) {
    my ($self, $c) = @_;
    $c->stash(template => 'invoice/invoice.tt'); 
}

sub invoice_template :Chained('invoice_details_calls') :PathPart('template') :Args {
    my ($self, $c) = @_;
    $c->log->debug('invoice_template');
    no warnings 'uninitialized';

    my($validator,$backend,$in,$out);

    #input
    (undef,undef,@$in{qw/tt_type tt_viewmode tt_sourcestate tt_output_type tt_id/}) = @_ ;
    $in->{contract_id} = $c->stash->{provider}->id;
    #$in->{client_id} = ;
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
            #$c->stash( to_json( { aaData => $aaData} ) ); 
            #$c->detach( $c->view('SVG') );#ie doesn't serve correctly json
            $c->response->body( to_json( { aaData => $aaData} ) );
            #$c->detach( $c->view('SVG') );#ie doesn't serve correctly json
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
