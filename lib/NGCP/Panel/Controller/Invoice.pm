package NGCP::Panel::Controller::Invoice;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Invoice;
use NGCP::Panel::Form::Invoice::Invoice;
use HTML::Entities;


sub auto :Private {
    my ($self, $c) = @_;
    $c->log->debug(__PACKAGE__ . '::auto');
    NGCP::Panel::Utils::Navigation::check_redirect_chain(c => $c);
    return 1;
}

sub inv_list :Chained('/') :PathPart('invoice') :CaptureArgs(0) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ( $self, $c ) = @_;

    $c->stash->{inv_rs} = $c->model('DB')->resultset('invoices');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $c->stash->{inv_rs} = $c->stash->{inv_rs}->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $c->stash->{inv_rs} = $c->stash->{inv_rs}->search({
            contract_id => $c->user->account_id,
        });
    };

    $c->stash->{inv_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => 'id', search => 1, title => $c->loc('#') },
        { name => 'contract.id', search => 1, title => $c->loc('Customer #') },
        { name => 'contract.contact.email', search => 1, title => $c->loc('Customer Email') },
        { name => 'serial', search => 1, title => $c->loc('Serial') },
    ]);

    $c->stash(template => 'invoice/invoice_list.tt');
}

sub customer_inv_list :Chained('/') :PathPart('invoice/customer') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(subscriberadmin) {
    my ( $self, $c, $contract_id ) = @_;

    $c->stash->{inv_dt_columns} = NGCP::Panel::Utils::Datatables::set_columns($c, [
        { name => "id", search => 1, title => $c->loc("#") },
        { name => "serial", search => 1, title => $c->loc("Serial #") },
        { name => "period_start", search => 1, title => $c->loc("Start") },
        { name => "period_end", search => 1, title => $c->loc("End") },
        { name => "amount_net", search => 1, title => $c->loc("Net Amount") },
        { name => "amount_vat", search => 1, title => $c->loc("VAT Amount") },
        { name => "amount_total", search => 1, title => $c->loc("Total Amount") },
    ]);

    unless($contract_id && is_int($contract_id)) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "Invalid contract id $contract_id found",
            desc  => $c->loc('Invalid contract id found'),
        );
        #NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }
    if($c->user->roles eq "subscriberadmin" && $c->user->account_id != $contract_id) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "access violation, subscriberadmin ".$c->user->uuid." with contract id ".$c->user->account_id." tries to access foreign contract id $contract_id",
            desc  => $c->loc('Invalid contract id found'),
        );
        #NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }
    my $contract = $c->model('DB')->resultset('contracts')->find($contract_id);
    unless($contract) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => "Contract id $contract_id not found",
            desc  => $c->loc('Invalid contract id detected'),
        );
        #NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/sound'));
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }

    $c->stash(inv_rs => $c->model('DB')->resultset('invoices')->search({
        contract_id => $contract->id,
    }));
    #$c->stash(template => 'sound/list.tt');
    $c->stash(template => 'invoice/invoice_list.tt');
    return;
}

sub root :Chained('inv_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('inv_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{inv_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{inv_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub customer_ajax :Chained('customer_inv_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{inv_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{inv_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('inv_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $inv_id) = @_;

    unless($inv_id && is_int($inv_id)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invalid invoice id detected',
            desc  => $c->loc('Invalid invoice id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }

    my $res = $c->stash->{inv_rs}->find($inv_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message::error(
            c     => $c,
            log   => 'Invoice does not exist',
            desc  => $c->loc('Invoice does not exist'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }
    $c->stash(inv => $res);
}

sub create :Chained('inv_list') :PathPart('create') :Args() :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) {
    my ($self, $c) = @_;

    my $posted = ($c->request->method eq 'POST');
    my $params = {};
    $params = merge($params, $c->session->{created_objects});

    my $form;
    $form = NGCP::Panel::Form::Invoice::Invoice->new(ctx => $c);
    $form->process(
        posted => $posted,
        params => $c->request->params,
        item   => $params,
    );
    NGCP::Panel::Utils::Navigation::check_form_buttons(
        c => $c,
        form => $form,
        fields => { },
        back_uri => $c->req->uri,
    );
    if($posted && $form->validated) {
        try {
            my $invoice_data = {};
            my $contract_id = $form->values->{contract}{id};
            my $customer_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c, contract_id => $contract_id);
            my $customer = $customer_rs->find({ 'me.id' => $contract_id });
            unless($customer) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => "invalid contract_id $contract_id",
                    desc  => $c->loc('Customer not found'),
                );
                die;
            }
            delete $form->values->{contract};
            $invoice_data->{contract_id} = $form->values->{contract_id} = $contract_id;

            my $tmpl_id = $form->values->{template}{id};
            delete $form->values->{template};
            
            my $tmpl = $schema->resultset('invoice_templates')->search({
                id => $tmpl_id,
            });
            if($c->user->roles eq "admin") {
            } elsif($c->user->roles eq "reseller") {
                $tmpl = $tmpl->search({
                    reseller_id => $c->user->reseller_id,
                });
            }
            $tmpl = $tmpl->first;
            unless($tmpl) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => "invalid template id $tmpl_id",
                    desc  => $c->loc('Invoice template not found'),
                );
                die;
            }
            unless($tmpl->data) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => "invalid template id $tmpl_id, data is empty",
                    desc  => $c->loc('Invoice template does not have an SVG stored yet'),
                );
                die;
            }

            unless($customer->contact->reseller_id == $tmpl->reseller_id) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => "template id ".$tmpl->id." has different reseller than contract id $contract_id",
                    desc  => $c->loc('Template and customer must belong to same reseller'),
                );
                die;
            }

            my $stime = NGCP::Panel::Utils::DateTime::from_string(
                delete $form->values->{period}
            )->truncate(to => 'month');
            my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);

            my($invoice_creation_error) = NGCP::Panel::Utils::Invoice::create_invoice($c,{
                contract_id  = $contract_id,
                customer     = $customer,
                stime        = $stime,
                etime        = $etime,
                tmpl         = $tmpl,
                invoice_data = $invoice_data,
            });
            if(!$invoice_creation_error){
                NGCP::Panel::Utils::Message::info(
                    c     => $c,
                    cname => 'create',
                    log   => $vars->{invoice},
                    desc  => $c->loc('Invoice #[_1] successfully created', $invoice->id),
                );
            }else{
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $invoice_creation_error,
                    desc  => $c->loc('Failed to create invoice data.'),
                );
                die($invoice_creation_error);                
            }
        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create invoice.'),
            );
            NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
        }
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub delete :Chained('base') :PathPart('delete') {
    my ($self, $c) = @_;

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub{
            $c->stash->{inv}->delete;
        });
        NGCP::Panel::Utils::Message::info(
            c    => $c,
            data => { $c->stash->{inv}->get_inflated_columns },
            desc => $c->loc('Invoice successfully deleted'),
        );
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete invoice .'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
}

sub download :Chained('base') :PathPart('download') {
    my ($self, $c) = @_;

    try {
        $c->response->content_type('application/pdf');
        $c->response->body($c->stash->{inv}->data);
        return;
    } catch($e) {
        NGCP::Panel::Utils::Message::error(
            c => $c,
            error => $e,
            desc  => $c->loc('Failed to delete invoice .'),
        );
    }
    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
}

__PACKAGE__->meta->make_immutable;
1;

# vim: set tabstop=4 expandtab:
