package NGCP::Panel::Controller::Invoice;
use Sipwise::Base;
use namespace::sweep;
BEGIN { extends 'Catalyst::Controller'; }

use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Invoice;
use NGCP::Panel::Form::Invoice::Invoice;

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

sub root :Chained('inv_list') :PathPart('') :Args(0) {
    my ($self, $c) = @_;
}

sub ajax :Chained('inv_list') :PathPart('ajax') :Args(0) {
    my ($self, $c) = @_;
    my $rs = $c->stash->{inv_rs};
    NGCP::Panel::Utils::Datatables::process($c, $rs, $c->stash->{inv_dt_columns});
    $c->detach( $c->view("JSON") );
}

sub base :Chained('inv_list') :PathPart('') :CaptureArgs(1) {
    my ($self, $c, $inv_id) = @_;

    unless($inv_id && $inv_id->is_integer) {
        NGCP::Panel::Utils::Message->error(
            c     => $c,
            log   => 'Invalid invoice id detected',
            desc  => $c->loc('Invalid invoice id detected'),
        );
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
    }

    my $res = $c->stash->{inv_rs}->find($inv_id);
    unless(defined($res)) {
        NGCP::Panel::Utils::Message->error(
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
    $params = $params->merge($c->session->{created_objects});

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
            my $schema = $c->model('DB');
            $schema->txn_do(sub {
                my $contract_id = $form->params->{contract}{id};
                my $customer_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c);
                my $customer = $customer_rs->find({ 'me.id' => $contract_id });
                unless($customer) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => "invalid contract_id $contract_id",
                        desc  => $c->loc('Customer not found'),
                    );
                    die;
                }
                delete $form->params->{contract};
                $form->params->{contract_id} = $contract_id;

                my $tmpl_id = $form->params->{template}{id};
                delete $form->params->{template};

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
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => "invalid template id $tmpl_id",
                        desc  => $c->loc('Invoice template not found'),
                    );
                    die;
                }
                unless($tmpl->data) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => "invalid template id $tmpl_id, data is empty",
                        desc  => $c->loc('Invoice template does not have an SVG stored yet'),
                    );
                    die;
                }

                unless($customer->contact->reseller_id == $tmpl->reseller_id) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => "template id ".$tmpl->id." has different reseller than contract id $contract_id",
                        desc  => $c->loc('Template and customer must belong to same reseller'),
                    );
                    die;
                }

                my $stime = NGCP::Panel::Utils::DateTime::from_string(
                    delete $form->params->{period}
                )->truncate(to => 'month');
                my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);

                my $zonecalls = NGCP::Panel::Utils::Contract::get_contract_zonesfees(
                    c => $c,
                    contract_id => $contract_id,
                    stime => $stime,
                    etime => $etime,
                    in => 0,
                    out => 1,
                    group_by_detail => 1,
                );
                my $calllist_rs = NGCP::Panel::Utils::Contract::get_contract_calls_rs(
                    c => $c,
                    customer_contract_id => $contract_id,
                    stime => $stime,
                    etime => $etime,
                );
                my $calllist = [ map { 
                    my $call = {$_->get_inflated_columns};
                    $call->{start_time} = $call->{start_time}->epoch;
                    $call->{source_customer_cost} += 0.0; # make sure it's a number
                    $call;
                } $calllist_rs->all ];
                
                my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
                my $billing_profile = $billing_mapping->billing_profile;

                my $balance;
                try {
                    $balance = NGCP::Panel::Utils::Contract::get_contract_balance(
                                c => $c,
                                profile => $billing_profile,
                                contract => $customer,
                                stime => $stime,
                                etime => $etime
                    );
                } catch($e) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => $e,
                        desc  => $c->loc('Failed to get contract balance.'),
                    );
                    die;
                }

                my $invoice_amounts = NGCP::Panel::Utils::Invoice::get_invoice_amounts(
                    customer_contract => {$customer->get_inflated_columns},
                    billing_profile   => {$billing_profile->get_inflated_columns},
                    contract_balance  => {$balance->get_inflated_columns},
                );
                @{$form->params}{qw/amount_net amount_vat amount_total/} = @$invoice_amounts{qw/amount_net amount_vat amount_total/};

                # generate tmp serial here, derive one from after insert
                $form->params->{serial} = "tmp".time.int(rand(99999));
                $form->params->{data} = undef;
                
                #maybe inflation should be applied? Generation failed here, although the latest schema applied.
                $form->params->{period_start} = $stime->ymd.' '. $stime->hms;
                $form->params->{period_end} = $etime->ymd.' '. $etime->hms;
                my $invoice;
                try {
                    $invoice = $schema->resultset('invoices')->create($form->params);
                } catch($e) {
                    NGCP::Panel::Utils::Message->error(
                        c => $c,
                        error => $e,
                        desc  => $c->loc('Failed to save invoice meta data.'),
                    );
                    die;
                }
                #sprintf("INV%04d%02d%07d", $stime->year, $stime->month, $invoice->id);
                #to make it unified for web and cron script
                my $serial = NGCP::Panel::Utils::Invoice::get_invoice_serial($c,{
                    invoice=>{
                        period_start => $stime,
                        period_end   => $etime,
                        id           => $invoice->id,
                }});

                my $svg = $tmpl->data;
                my $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();
                my $out = '';
                my $pdf = '';
                my $vars = {};

                # TODO: index 170 seems the upper limit here, then the calllist breaks

                $vars->{rescontact} = { $customer->contact->reseller->contract->contact->get_inflated_columns };
                $vars->{customer} = { $customer->get_inflated_columns };
                $vars->{custcontact} = { $customer->contact->get_inflated_columns };
                
                $vars->{custcontact}->{country} = $customer->contact->country_name();
                $vars->{rescontact}->{country}  = $customer->contact->reseller->contract->contact->country_name();
                
                $vars->{billprof} = { $billing_profile->get_inflated_columns };
                $vars->{invoice} = {
                    period_start => $stime,
                    period_end => $etime,
                    serial => $serial,
                    amount_net => $form->params->{amount_net},
                    amount_vat => $form->params->{amount_vat},
                    amount_total => $form->params->{amount_total},
                };
                $vars->{calls} = $calllist,
                $vars->{zones} = {
                    totalcost => $balance->cash_balance_interval,
                    data => [ values(%{ $zonecalls }) ],
                };

                try {

                    $t->process(\$svg, $vars, \$out) || do {
                        my $error = $t->error();
                        my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
                        NGCP::Panel::Utils::Message->error(
                            c     => $c,
                            log   => $msg,
                            desc  => $c->loc('Failed to render template. Type is ' . $error->type . ', info is ' . $error->info),
                        );
                        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
                        return;
                    };
                    NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$out);

                    NGCP::Panel::Utils::InvoiceTemplate::svg_pdf($c, \$out, \$pdf);
                } catch($e) {
                    NGCP::Panel::Utils::Message->error(
                        c     => $c,
                        log   => $e,
                        desc  => $c->loc('Failed to render invoice'),
                    );
                    NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
                    return;
                }

                $invoice->update({
                    serial => $serial,
                    data => $pdf,
                });
                $c->flash(messages => [{type => 'success', text => $c->loc('Invoice #' . $invoice->id . ' successfully created')}]);
            });
        } catch($e) {
            NGCP::Panel::Utils::Message->error(
                c => $c,
                error => $e,
                desc  => $c->loc('Failed to create invoice.'),
            );
        }
        NGCP::Panel::Utils::Navigation::back_or($c, $c->uri_for('/invoice'));
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
        $c->flash(messages => [{type => 'success', text => $c->loc('Invoice successfully deleted')}]);
    } catch($e) {
        NGCP::Panel::Utils::Message->error(
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
        NGCP::Panel::Utils::Message->error(
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
