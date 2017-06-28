package NGCP::Panel::Utils::Invoice;

use Sipwise::Base;
use NGCP::Panel::Utils::ProfilePackages;

use HTML::Entities;
use Geography::Countries qw/country/;


sub get_invoice_amounts{
    my(%params) = @_;
    my($customer_contract,$billing_profile,$contract_balance) = @params{qw/customer_contract billing_profile contract_balance/};
    my $invoice = {};
    $contract_balance->{cash_balance_interval} //= 0;
    $billing_profile->{interval_charge} //= 0;
    $customer_contract->{vat_rate} //= 0;
    #use Data::Dumper;
    #print Dumper [$contract_balance,$billing_profile]; 
    $invoice->{amount_net} = $contract_balance->{cash_balance_interval} / 100 + $billing_profile->{interval_charge};
    $invoice->{amount_vat} = 
        $customer_contract->{add_vat} 
        ?
            $invoice->{amount_net} * ($customer_contract->{vat_rate}/100) 
            : 0,
    $invoice->{amount_total} =  $invoice->{amount_net} + $invoice->{amount_vat};
    return $invoice;
}

sub get_invoice_serial{
    my($c,$params) = @_;
    my($invoice) = @$params{qw/invoice/};
    return sprintf("INV%04d%02d%07d", $invoice->{period_start}->year,  $invoice->{period_start}->month, $invoice->{id});
}

sub prepare_contact_data{
    my($contact) = @_;
    $contact->{country} = country($contact->{country} || 0);
    foreach(keys %$contact){
        $contact->{$_} = encode_entities($contact->{$_}, '<>&"');
    }
    #passed by reference
    #return $contact;
}

sub create_invoice{
    my($c,$params) = @_;
    my($contract_id,$customer,$stime,$etime,$tmpl,$invoice_data) = @$params{qw/contract_id customer stime etime tmpl invoice_data/};

    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');
    $schema->txn_do(sub {
        #this has to be refactored  - select a contract balance instead of a "period"
        try {
            my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(
                c => $c,
                contract => $customer,
                stime => $stime,
                etime => $etime,);
            $stime = $balance->start;
            $etime = $balance->end;
            my $bm_actual = NGCP::Panel::Utils::ProfilePackages::get_actual_billing_mapping(
                c => $c, 
                contract => $customer, 
                now => $balance->start);
            my $billing_profile = $bm_actual->billing_mappings->first->billing_profile;

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
                $call->{destination_user_in} =~s/%23/#/g;
                #$call->{destination_user_in} = encode_entities($call->{destination_user_in}, '<>&"#');
                $call->{source_customer_cost} += 0.0; # make sure it's a number
                $call;
            } $calllist_rs->all ];

            #my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
            #my $billing_profile = $billing_mapping->billing_profile;
            #try {
            #   $balance = NGCP::Panel::Utils::Contract::get_contract_balance(
            #               c => $c,
            #               profile => $billing_profile,
            #               contract => $customer,
            #               stime => $stime,
            #               etime => $etime
            #   );
            #} catch($e) {
            #    NGCP::Panel::Utils::Message::error(
            #        c => $c,
            #        error => $e,
            #        desc  => $c->loc('Failed to get contract balance.'),
            #    );
            #    die;
            #}

            my $invoice_amounts = get_invoice_amounts(
                customer_contract => {$customer->get_inflated_columns},
                billing_profile   => {$billing_profile->get_inflated_columns},
                contract_balance  => {$balance->get_inflated_columns},
            );
            @{$invoice_data}{qw/amount_net amount_vat amount_total/} = @$invoice_amounts{qw/amount_net amount_vat amount_total/};

            # generate tmp serial here, derive one from after insert
            $invoice_data->{serial} = "tmp".time.int(rand(99999));
            $invoice_data->{data} = undef;

            #maybe inflation should be applied? Generation failed here, although the latest schema applied.
            $invoice_data->{period_start} = $stime->ymd.' '. $stime->hms;
            $invoice_data->{period_end} = $etime->ymd.' '. $etime->hms;
            my $invoice;
            try {
                $invoice = $schema->resultset('invoices')->create($invoice_data);
            } catch($e) {
                NGCP::Panel::Utils::Message::error(
                    c => $c,
                    error => $e,
                    desc  => $c->loc('Failed to save invoice meta data.'),
                );
                die($e);
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
            utf8::decode($svg);
            my $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();
            my $out = '';
            my $pdf = '';
            my $vars = {};

            # TODO: index 170 seems the upper limit here, then the calllist breaks

            $vars->{rescontact} = { $customer->contact->reseller->contract->contact->get_inflated_columns };
            $vars->{customer} = { $customer->get_inflated_columns };
            $vars->{custcontact} = { $customer->contact->get_inflated_columns };
            $vars->{billprof} = { $billing_profile->get_inflated_columns };

            prepare_contact_data($vars->{billprof});
            prepare_contact_data($vars->{custcontact});
            prepare_contact_data($vars->{rescontact});

            $vars->{invoice} = {
                period_start => $stime,
                period_end   => $etime,
                serial       => $serial,
                amount_net   => $invoice_data->{amount_net},
                amount_vat   => $invoice_data->{amount_vat},
                amount_total => $invoice_data->{amount_total},
            };
            $vars->{calls} = $calllist,
            $vars->{zones} = {
                totalcost => $balance->cash_balance_interval,
                data => [ values(%{ $zonecalls }) ],
            };


            $t->process(\$svg, $vars, \$out) || do {
                my $error = $t->error();
                my $msg = "error processing template, type=".$error->type.", info='".$error->info."'";
                NGCP::Panel::Utils::Message::error(
                    c     => $c,
                    log   => $msg,
                    desc  => $c->loc('Failed to render template. Type is [_1], info is [_2].', $error->type, $error->info),
                );
                die($e);
            };
            NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$out);

            NGCP::Panel::Utils::InvoiceTemplate::svg_pdf($c, \$out, \$pdf);

            $invoice->update({
                serial => $serial,
                data => $pdf,
            });
        }catch($e) {
           NGCP::Panel::Utils::Message::error(
                c     => $c,
                log   => $msg,
                desc  => $c->loc('Failed to create invoice'),
            );
            return ($e);
        }
    });
}
1;
# vim: set tabstop=4 expandtab:
