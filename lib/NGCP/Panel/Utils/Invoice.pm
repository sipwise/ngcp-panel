package NGCP::Panel::Utils::Invoice;

use Sipwise::Base;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::BillingMappings qw();
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::Message;
use NGCP::Panel::Utils::CallList;
use HTML::Entities;
use Geography::Countries qw/country/;
use HTTP::Status qw(:constants);

sub get_invoice_amounts {
    my(%params) = @_;
    my($customer_contract,$billing_profile,$contract_balance,$zonecalls,$category) = @params{qw/customer_contract billing_profile contract_balance zonecalls category/};
    my $invoice = {};
    $billing_profile->{interval_charge} //= 0.0;
    $customer_contract->{vat_rate} //= 0.0;
    if ($zonecalls) {
        $invoice->{amount_net} = 0.0;
        map {
            if ($category eq 'customer' or $category eq 'did') {
                $invoice->{amount_net} += $_->{customercost};
            } elsif ($category eq 'reseller') {
                $invoice->{amount_net} += $_->{resellercost};
            } elsif ($category eq 'peer') {
                $invoice->{amount_net} += $_->{carriercost};
            }
        } values %$zonecalls;
    } else {
        $contract_balance->{cash_balance_interval} //= 0.0;
        #use Data::Dumper;
        #print Dumper [$contract_balance,$billing_profile];
        $invoice->{amount_net} = ($contract_balance->{cash_balance_interval} + $billing_profile->{interval_charge}) / 100.0;
    }
    $invoice->{amount_vat} =
        $customer_contract->{add_vat}
        ?
            $invoice->{amount_net} * ($customer_contract->{vat_rate} / 100.0)
            : 0.0;
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

sub create_invoice {
    my($c,$params) = @_;
    my($contract,$stime,$etime,$tmpl,$invoice_data) = @$params{qw/contract stime etime tmpl invoice_data/};

    my $invoice;

    my $schema = $c->model('DB');
    $schema->set_wait_timeout(1800);
    #this has to be refactored  - select a contract balance instead of a "period"
    my $balance = NGCP::Panel::Utils::ProfilePackages::get_contract_balance(
        c => $c,
        contract => $contract,
        stime => $stime,
        etime => $etime,);
    $stime = $balance->start;
    $etime = $balance->end;
    my $bm_actual = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(
        c => $c,
        contract => $contract,
        now => $balance->start);
    my $billing_profile = $bm_actual->billing_profile;
    my $zonecalls = {};
    my $did_zonecalls = [];
    if ($tmpl->category eq 'did') {
        foreach my $subs ($schema->resultset('voip_subscribers')->search({
                contract_id => $contract->id,
                #status => { '!=' => 'terminated' },
                #'provisioning_voip_subscriber.is_pbx_group' => 0,
            }, #{
                #join => 'provisioning_voip_subscriber',
            #}
            )->all) {
            my $zc = NGCP::Panel::Utils::Contract::get_contract_zonesfees(
                c => $c,
                contract_id => $contract->id,
                stime => $stime,
                etime => $etime,
                call_direction => $tmpl->call_direction,
                group_by_detail => 1,
                category => $tmpl->category,
                subscriber_uuid => $subs->uuid,
            );
            my $s = { $subs->get_inflated_columns };
            $s->{primary_number} = { $subs->primary_number->get_inflated_columns } if $subs->primary_number;
            $s->{prov_subscriber} = { $subs->provisioning_voip_subscriber->get_inflated_columns } if $subs->provisioning_voip_subscriber;
            push(@$did_zonecalls,{
                subscriber => $s,
                zonecalls => $zc,
                totalcost => 0.0,
                totalduration => 0.0,
            }) if scalar keys %$zc;
        }
    }
    $zonecalls = NGCP::Panel::Utils::Contract::get_contract_zonesfees(
        c => $c,
        contract_id => $contract->id,
        stime => $stime,
        etime => $etime,
        call_direction => $tmpl->call_direction,
        group_by_detail => 1,
        category => $tmpl->category,
    );    
    
    my $calllist = [];
    if ($tmpl->category eq 'customer') {
        my $calllist_rs = NGCP::Panel::Utils::Contract::get_contract_calls_rs(
            c => $c,
            contract_id => $contract->id,
            stime => $stime,
            etime => $etime,
            call_direction => $tmpl->call_direction,
            category => $tmpl->category,
        );
        $calllist = [ map {
            my $call = {$_->get_inflated_columns};
            $call->{start_time} = $call->{start_time}->epoch;
            $call->{destination_user_in} =~s/%23/#/g;
            #$call->{destination_user_in} = encode_entities($call->{destination_user_in}, '<>&"#');
            $call->{source_customer_cost} += 0.0; # make sure it's a number
            $call->{source_reseller_cost} += 0.0 if exists $call->{source_reseller_cost};
            $call->{source_carrier_cost} += 0.0 if exists $call->{source_carrier_cost};
            NGCP::Panel::Utils::CallList::suppress_cdr_fields($c,$call,$_);
        } $calllist_rs->all ];
    }

    my $invoice_amounts = get_invoice_amounts(
        customer_contract => {$contract->get_inflated_columns}, #support legacy
        contract => {$contract->get_inflated_columns},
        billing_profile   => {$billing_profile->get_inflated_columns},
        contract_balance  => {$balance->get_inflated_columns},
        zonecalls         => $zonecalls,
        category => $tmpl->category,
    );
    @{$invoice_data}{qw/amount_net amount_vat amount_total/} = @$invoice_amounts{qw/amount_net amount_vat amount_total/};

    # generate tmp serial here, derive one from after insert
    $invoice_data->{serial} = "tmp".time.int(rand(99999));
    $invoice_data->{data} = undef;
    #maybe inflation should be applied? Generation failed here, although the latest schema applied.
    $invoice_data->{period_start} = $stime->ymd.' '. $stime->hms;
    $invoice_data->{period_end} = $etime->ymd.' '. $etime->hms;
    try {
        $invoice = $schema->resultset('invoices')->create($invoice_data);
    } catch($e) {
        die {
            showdetails => $c->loc('Failed to save invoice meta data.'),
            error => $e,
            httpcode => HTTP_UNPROCESSABLE_ENTITY,
        };
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

    $vars->{rescontact} = { $contract->contact->reseller->contract->contact->get_inflated_columns } if $contract->contact->reseller;
    $vars->{customer} = { $contract->get_inflated_columns };
    $vars->{contract} = { $contract->get_inflated_columns };
    $vars->{custcontact} = { $contract->contact->get_inflated_columns };
    $vars->{contact} = { $contract->contact->get_inflated_columns };
    $vars->{billprof} = { $billing_profile->get_inflated_columns };

    prepare_contact_data($vars->{billprof});
    prepare_contact_data($vars->{custcontact});
    prepare_contact_data($vars->{contact});
    prepare_contact_data($vars->{rescontact});

    $vars->{invoice} = {
        period_start => $stime,
        period_end   => $etime,
        serial       => $serial,
        amount_net   => $invoice_data->{amount_net},
        amount_vat   => $invoice_data->{amount_vat},
        amount_total => $invoice_data->{amount_total},
        contract_balance => { $balance->get_inflated_columns },
        call_direction => ($tmpl->call_direction eq 'in' ? 'from' : ($tmpl->call_direction eq 'out' ? 'to' : ($tmpl->call_direction eq 'in_out' ? 'from/to' : ''))),
    };
    $vars->{calls} = $calllist;
    $vars->{zones} = {
        totalcost => 0.0,
        totalduration => 0.0,
        data => [ values(%{ $zonecalls }) ],
    };
    map {
        if ($tmpl->category eq 'customer' or $tmpl->category eq 'did') {
            $vars->{zones}->{totalcost} += $_->{customercost};
        } elsif ($tmpl->category eq 'reseller') {
            $vars->{zones}->{totalcost} += $_->{resellercost};
        } elsif ($tmpl->category eq 'peer') {
            $vars->{zones}->{totalcost} += $_->{carriercost};
        }
        $vars->{zones}->{totalduration} += $_->{duration};
    } values %$zonecalls;
    
    map {
        my $did_zc = $_;
        map {
            if ($tmpl->category eq 'customer' or $tmpl->category eq 'did') {
                $did_zc->{totalcost} += $_->{customercost};
            } elsif ($tmpl->category eq 'reseller') {
                $did_zc->{totalcost} += $_->{resellercost};
            } elsif ($tmpl->category eq 'peer') {
                $did_zc->{totalcost} += $_->{carriercost};
            }
            $did_zc->{totalduration} += $_->{duration};
            $did_zc->{data} = [ values(%{ delete $did_zc->{zonecalls} }) ];
        } values %{$did_zc->{zonecalls}};
    } @$did_zonecalls;
    $vars->{did_zones} = $did_zonecalls;
    
    #use Data::Dumper;
    #$c->log->debug(Dumper($did_zonecalls));

    $t->process(\$svg, $vars, \$out) || do {
        my $error = $t->error();
        my $error_msg = "error processing template, type=".$error->type.", info='".$error->info."'";
        my $msg =$c->loc('Failed to render template. Type is [_1], info is [_2].', $error->type, $error->info);
        die {
            showdetails => $msg,
            error => $error_msg,
            httpcode => HTTP_UNPROCESSABLE_ENTITY,
        };
    };
    NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$out);

    NGCP::Panel::Utils::InvoiceTemplate::svg_pdf($c, \$out, \$pdf);

    $invoice->update({
        serial => $serial,
        data   => $pdf,
    });

    NGCP::Panel::Utils::Message::info(
        c     => $c,
        cname => 'create',
        log   => $vars->{invoice},
        desc  => $c->loc('Invoice #[_1] successfully created', $invoice->id),
    );
    return $invoice;
}

sub check_invoice_data{
    my ($c,$params) = @_;
    my ($contract_id,$tmpl_id,$period,$period_start,$period_end) = @$params{qw/contract_id tmpl_id period period_start period_end/};

    my $invoice_data = {};

    my $schema = $c->model('DB');
    
    my $tmpl = $schema->resultset('invoice_templates')->search({
        id => $tmpl_id,
    });

    if ($c->user->roles eq "admin") {
    } elsif ($c->user->roles eq "reseller") {
        $tmpl = $tmpl->search({
            reseller_id => $c->user->reseller_id,
        });
    }

    $tmpl = $tmpl->first;
    unless ($tmpl) {
        die {
            showdetails => $c->loc('Invoice template not found'),
            error => "invalid template id $tmpl_id",
            httpcode => HTTP_UNPROCESSABLE_ENTITY,
        };
    }
    unless ($tmpl->data) {
        die {
            showdetails => $c->loc('Invoice template does not have an SVG stored yet'),
            error => "invalid template id $tmpl_id, data is empty",
            httpcode => HTTP_UNPROCESSABLE_ENTITY,
        };
    }
    
    my $contract;
    if ('customer' eq $tmpl->category or 'did' eq $tmpl->category) {
        $contract = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c)->find({ 'me.id' => $contract_id });
        unless($contract) {
            die {
                showdetails => $c->loc('Customer not found'),
                error => "invalid contract_id $contract_id",
                httpcode => HTTP_UNPROCESSABLE_ENTITY,
            };
        }
  
        unless($contract->contact->reseller_id == $tmpl->reseller_id) {
            die {
                showdetails => $c->loc('Template and customer must belong to same reseller'),
                error => "template id ".$tmpl->id." has different reseller than contract id $contract_id",
                httpcode => HTTP_UNPROCESSABLE_ENTITY,
            };
        }
    } else {
        
        my @product_ids = map { $_->id; } $schema->resultset('products')->search_rs({ 'class' => ['pstnpeering','sippeering','reseller'] })->all;
        $contract = NGCP::Panel::Utils::Contract::get_contract_rs(c => $c)->search_rs({
            'me.id' => $contract_id,
            'product_id' => { -in => [ @product_ids ] },
        },{
            join => 'contact',
        })->first;
        
        unless($contract) {
            die {
                showdetails => $c->loc('Contract not found'),
                error => "invalid contract_id $contract_id",
                httpcode => HTTP_UNPROCESSABLE_ENTITY,
            };
        }

    }
    
    $invoice_data->{contract_id} = $contract_id;
    #$invoice_data->{category} = $tmpl->category;

    my $stime = $period_start ? NGCP::Panel::Utils::DateTime::from_string(
        $period_start
    ) : NGCP::Panel::Utils::DateTime::from_string(
        $period
    )->truncate(to => 'month');
    my $etime = $period_end ? NGCP::Panel::Utils::DateTime::from_string(
        $period_end
    ) : $stime->clone->add(months => 1)->subtract(seconds => 1);

    return ($contract,$tmpl,$stime,$etime,$invoice_data);
    
}

1;