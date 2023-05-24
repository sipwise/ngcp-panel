package NGCP::Panel::Controller::Invoice;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use parent 'Catalyst::Controller';

use NGCP::Panel::Form;

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Invoice;
use NGCP::Panel::Utils::CallList qw();
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
        { name => 'contract.id', search => 1, title => $c->loc('Contract #') },
        { name => 'contract.contact.email', search => 1, title => $c->loc('Contract Email') },
        { name => 'contract.product.name', search => 1, title => $c->loc('Product #') },
        { name => 'serial', search => 1, title => $c->loc('Serial') },
    ]);

    $c->stash(template => 'invoice/invoice_list.tt');
}

sub customer_inv_list :Chained('/') :PathPart('invoice/customer') :CaptureArgs(1) :Does(ACL) :ACLDetachTo('/denied_page') :AllowedRole(admin) :AllowedRole(reseller) :AllowedRole(ccareadmin) :AllowedRole(ccare) :AllowedRole(subscriberadmin) {
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
            error => "access violation, subscriberadmin ".$c->qs($c->user->uuid)." with contract id ".$c->user->account_id." tries to access foreign contract id $contract_id",
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

    my $schema = $c->model('DB');
    my $form;
    $form = NGCP::Panel::Form::get("NGCP::Panel::Form::Invoice::Invoice", $c);
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
            my $contract_id = $form->values->{contract}{id};
            delete $form->values->{customer};
            my $tmpl_id = $form->values->{template}{id};
            delete $form->values->{template};
            my $period = delete $form->values->{period};
            my($contract,$tmpl,$stime,$etime,$invoice_data);

            ($contract,$tmpl,$stime,$etime,$invoice_data) = NGCP::Panel::Utils::Invoice::check_invoice_data($c, {
                contract_id  => $contract_id,
                tmpl_id      => $tmpl_id,
                period_start => undef,
                period_end   => undef,
                period       => $period,
            });

            $schema->set_transaction_isolation('READ COMMITTED');
            $schema->txn_do(sub {
                NGCP::Panel::Utils::Invoice::create_invoice($c,{
                    contract     => $contract,
                    stime        => $stime,
                    etime        => $etime,
                    tmpl         => $tmpl,
                    invoice_data => $invoice_data,
                });
            });

        } catch($e) {
            NGCP::Panel::Utils::Message::error(
                c     => $c,
                error => $e,
                desc  => $c->loc('Failed to create invoice'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }

    $c->stash(form => $form);
    $c->stash(create_flag => 1);
}

sub delete_invoice :Chained('base') :PathPart('delete') {
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

1;

# vim: set tabstop=4 expandtab:
