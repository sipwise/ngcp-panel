#!/usr/bin/perl -w
use lib '/media/sf_/usr/share/VMHost/ngcp-panel/lib';
use strict;

use Getopt::Long;
use DBI;
use Data::Dumper;
use DateTime::TimeZone;
use Test::MockObject;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;
use Template;
use Geography::Countries qw/country/;
#use IO::All;

#apt-get install libemail-send-perl
#apt-get install libemail-sender-perl
#apt-get install libtest-mockobject-perl

#apt-get install libnet-smtp-ssl-perl
#apt-get install libio-all-perl

use Sipwise::Base;

use NGCP::Panel;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Invoice;
use NGCP::Panel::Utils::Email;
#use NGCP::Panel::View::SVG;

my $debug = 0;

my ($dbuser, $dbpass);
my $mfile = '/etc/mysql/sipwise.cnf';
if(-f $mfile) {
    open my $fh, "<", $mfile
        or die "failed to open '$mfile': $!\n";
    $_ = <$fh>; chomp;
    s/^SIPWISE_DB_PASSWORD='(.+)'$/$1/;
    $dbuser = 'sipwise'; $dbpass = $_;
} else {
    $dbuser = 'root';
    $dbpass = '';
}
print "using user '$dbuser' with pass '$dbpass'\n"
    if($debug);

my $dbh = DBI->connect('dbi:mysql:billing;host=localhost', $dbuser, $dbpass)
    or die "failed to connect to billing DB\n";



my $opt = {};
Getopt::Long::GetOptions($opt, 'reseller_id:i@', 'client_contact_id:i@', 'client_contract_id:i@', 'stime:s', 'etime:s', 'send!','sendonly!','resend','year:i','month:i','help|?')
    or die 'could not process command-line options';
print Dumper $opt;

my $stime = $opt->{stime} 
    ? NGCP::Panel::Utils::DateTime::new_local(split(/\D+/,$opt->{stime})) 
    : NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
my $etime = $opt->{etime} 
    ? NGCP::Panel::Utils::DateTime::new_local(split(/\D+/,$opt->{etime})) 
    : $stime->clone->add( months => 1 )->subtract( seconds => 1 );
if( $opt->{client_contract_id} ){
    $opt->{reseller_id} = $dbh->selectall_arrayref('select distinct contacts.reseller_id from contracts inner join contacts on contracts.contact_id=contacts.id '.ify(' where contracts.id', @{$opt->{client_contract_id}}),  { Slice => {} }, @{$opt->{client_contract_id}} );
    $opt->{client_contact_id} = $dbh->selectall_arrayref('select distinct contracts.contact_id from contracts '.ify(' where contracts.id', @{$opt->{client_contract_id}}),  { Slice => {} }, @{$opt->{client_contract_id}} );
}

process_invoices();


sub process_invoices{

    my $invoices = {};

    foreach my $provider_contract( @{ get_providers_contracts($opt) } ){
        
        print "reseller_id=".$provider_contract->{reseller_core_id}.";\n";
        
        my $provider_contact = get_provider_contact($provider_contract);

        foreach my $client_contact (@{ get_provider_clients_contacts($provider_contract,$opt) } ){

            print "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";\n";
            
            $invoices->{$client_contact->{id}} ||= [];
            
            if(!$opt->{sendonly}){
                foreach my $client_contract (@{ get_client_contracts($client_contact,$opt) }){
                    
                    print "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";contract_id=".$client_contract->{id}.";\n";

                    if( my $billing_profile = get_billing_profile($client_contract, $stime, $etime) ){
                        if(my $invoice = generate_invoice_data($provider_contract,$provider_contact,$client_contract,$client_contact,$billing_profile, $stime, $etime)){
                            push @{$invoices->{$client_contact->{id}}}, $invoice;
                        }
                    }else{#if billing profile
                        print "No billing profile;\n"
                    }
                }#foreach client contract
            }else{
                $invoices->{$client_contact->{id}} = $dbh->selectall_arrayref('select invoices.* from invoices 
                inner join contract_balances on invoices.id=contract_balances.invoice_id 
                inner join contracts on contracts.id=contract_balances.contract_id
                '.ifp(' where ',
                    join(' and ',
                        !$opt->{resend}?' invoices.sent_date is null ':(),
                        (ify(' contracts.contact_id ', (@{$opt->{client_contact_id}}, $client_contact->{id}) )),
                        (ifk(' date(invoices.period_start) >= ?', v2a($stime->ymd))),
                        (ifk(' date(invoices.period_start) <= ?', v2a($etime->ymd))),
                    )
                ),  { Slice => {} }, @{$opt->{client_contact_id}}, v2a($client_contact->{id}), v2a($opt->{month}),v2a($opt->{year}) );
            }
            if($opt->{send} || $opt->{sendonly}){
                my $email_template = get_email_template($provider_contract);
                email($email_template, $provider_contact, $client_contact, $invoices->{$client_contact->{id}} );
            }
        }#foreach client contact
    }#foreach reseller
}

sub get_providers_contracts{
    my ($opt) = @_;
    return $dbh->selectall_arrayref('select contracts.*,resellers.id as reseller_core_id from resellers inner join contracts on resellers.contract_id=contracts.id where resellers.status != "terminated" '.ify(' and resellers.id ', @{$opt->{reseller_id}}),  { Slice => {} }, @{$opt->{reseller_id}} );
}
sub get_provider_contact{
    my($provider_contract) = @_;
    #todo: use selectall_hashref to don't query every time
    return $dbh->selectrow_hashref('select * from contacts where id=?', undef, $provider_contract->{contact_id} )
}
sub get_provider_clients_contacts{
    my($provider_contract, $opt) = @_;
    #according to /reseller/ajax_reseller_filter
    my $contacts = $dbh->selectall_arrayref('select contacts.* from contacts where reseller_id = ?'.ify(' and contacts.id', @{$opt->{client_contact_id}}),  { Slice => {} }, $provider_contract->{reseller_core_id}, @{$opt->{client_contact_id}} );
    #foreach (@$contacts){
    #    $_->{country_name} = country($_->{country});
    #}
    return $contacts;
}
sub get_client_contracts{
    my($client_contact, $opt) = @_;
    return $dbh->selectall_arrayref('select contracts.* from contracts where contracts.contact_id=? '.ify(' and contracts.id', @{$opt->{client_contract_id}}), { Slice => {} }, $client_contact->{id}, @{$opt->{client_contract_id}} );
}
sub get_billing_profile{
    my($client_contract, $stime, $etime) = @_;
    $dbh->selectrow_hashref('select distinct billing_profiles.* 
        from billing_mappings
        inner join billing_profiles on billing_mappings.billing_profile_id=billing_profiles.id
        inner join contracts on contracts.id=billing_mappings.contract_id
        inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
        where 
            contracts.status != "terminated"
            and contracts.id=?
            and (billing_mappings.start_date <= ? OR billing_mappings.start_date IS NULL)
            and (billing_mappings.end_date >= ? OR billing_mappings.end_date IS NULL)'
    , undef, $client_contract->{id}, $etime->epoch, $stime->epoch 
    );
}
sub get_invoice_data_raw{
    my($client_contract, $stime, $etime) = @_;

    my $invoice_details_calls = $dbh->selectall_arrayref('select cdr.*,from_unixtime(cdr.start_time) as start_time,bzh.zone, bzh.detail as zone_detail 
    from accounting.cdr 
    LEFT JOIN billing.billing_zones_history bzh ON bzh.id = cdr.source_customer_billing_zone_id
    where
    cdr.source_user_id != 0
    and cdr.call_status="ok" 
    and cdr.source_account_id=?
    and cdr.start_time >= ?
    and cdr.start_time <= ?
    order by cdr.start_time
    --          limit 25'
    , { Slice => {} }
    , $client_contract->{id},$stime->epoch,$etime->epoch
    );
    my $invoice_details_zones = $dbh->selectall_arrayref('select SUM(cdr.source_customer_cost) AS cost, COUNT(*) AS number, SUM(cdr.duration) AS duration,sum(cdr.source_customer_free_time) as free_time, bzh.zone
    from accounting.cdr 
    LEFT JOIN billing.billing_zones_history bzh ON bzh.id = cdr.source_customer_billing_zone_id
    where
    cdr.source_user_id != 0
    and cdr.call_status="ok" 
    and cdr.source_account_id=?
    and cdr.start_time >= ?
    and cdr.start_time <= ?
    group by bzh.zone
    order by bzh.zone'
    , {Slice => {} }
    , $client_contract->{id},$stime->epoch,$etime->epoch
    );
    #/data for invoice generation
    my $i = 1;
    $invoice_details_calls = [map{[$i++,$_]} (@$invoice_details_calls) x 1];
    $i = 1;
    $invoice_details_zones = [map{[$i++,$_]} (@$invoice_details_zones) x 1];
    my $stash = {
        invoice_details_zones => $invoice_details_zones,
        invoice_details_calls => $invoice_details_calls,
    };
    return $stash;
}
sub generate_invoice_data{
    my($provider_contract,$provider_contact,$client_contract,$client_contact,$billing_profile, $stime, $etime) = @_;
    
    state ($t,$svg_default);
    if(!$t){
        $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();        
        $svg_default = $t->context->insert('invoice/default/invoice_template_svg.tt');
        #NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$svg_default);
    }
    my $svg = $dbh->selectrow_array('select data from invoice_templates where  type = "svg" and reseller_id=?',undef,$provider_contract->{reseller_core_id});#is_active = 1 and
    if($svg){
        NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$svg);
    }else{
        #$svg = $svg_default;
        print "No saved active template - no invoice;\n";
        return;
    }

    my ($contract_balance,$invoice)=({},{});
    ($contract_balance,$invoice) = get_contract_balance($client_contract,$billing_profile,$contract_balance,$invoice,$stime,$etime);
    print Dumper $contract_balance;
    
    $client_contact->{country} = country($client_contact->{country} || '');
    $provider_contact->{country} = country($provider_contact->{country} || '');
    # TODO: if not a full month, calculate fraction?
    #TODO: to utils::contract and share with catalyst version
    my $invoice_amounts = NGCP::Panel::Utils::Invoice::get_invoice_amounts(
        customer_contract  => $client_contract,
        contract_balance   => $contract_balance,
        billing_profile    => $billing_profile,
    );
    $invoice = {
        %$invoice,
        %$invoice_amounts,
    };
    my($invoice_data) = get_invoice_data_raw($client_contract, $stime, $etime);
    my $out = '';
    my $pdf = '';
    my $vars = {
        invoice     => $invoice,
        rescontact  => $provider_contact,
        customer    => $client_contract,
        custcontact => $client_contact,
        billprof    => $billing_profile,
        calls       => $invoice_data->{invoice_details_calls},
        zones       => {
            totalcost => $contract_balance->{cash_balance_interval},
            data => $invoice_data->{invoice_details_zones},        
        },
    };
    $out = $t->context->process(\$svg, $vars);
    #for default template
    $out = '<root>'.$out.'</root>';
    NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$out);
    #for default template
    $out =~s/^<root>|<\/root>$//;
    NGCP::Panel::Utils::InvoiceTemplate::svg_pdf(undef, \$out, \$pdf);
    print "generated data for invoice.id=".$invoice->{id}."; invoice.serial=".$invoice->{serial}.";\n";
    $invoice->{data} = $pdf;
    #set sent_date to null after each data regeneration
    $dbh->do('update invoices set sent_date=?,data=?,amount_net=?,amount_vat=?,amount_total=? where id=?',undef,undef,@$invoice{qw/data amount_net amount_vat amount_total id/});    
    return $invoice;
}
sub get_contract_balance{
    my($client_contract,$billing_profile,$contract_balance,$invoice,$stime,$etime) = @_;
    if(!($contract_balance = $dbh->selectrow_hashref('select * from contract_balances where contract_id=? and date(start)=? and date(end)=?',undef,$client_contract->{id},$stime->ymd,$etime->ymd))){
        @$contract_balance{qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/} = NGCP::Panel::Utils::Contract::get_contract_balance_values(
            %$billing_profile,
            stime => $stime,
            etime => $etime,
        );
        $dbh->do('insert into contract_balances(contract_id,cash_balance,cash_balance_interval,free_time_balance,free_time_balance_interval,start,end,invoice_id)values(?,?,?,?,?,?,?,?)',undef,$client_contract->{id},@$contract_balance{qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/},$stime->datetime, $etime->datetime,undef );
        $invoice = get_invoice(undef, $client_contract->{id},$stime, $etime);
        #my $contract_balance_id = $dbh->last_insert_id(undef,'billing','contract_balances','id');
        #print "contract_balance_id=$contract_balance_id;\n";
        #$contract_balance = $dbh->selectrow_hashref('select * from contract_balances where id=?',undef,);  
        $contract_balance = $dbh->selectrow_hashref('select * from contract_balances where contract_id=? and date(start)=? and date(end)=?',undef,$client_contract->{id},$stime->ymd,$etime->ymd);
        print Dumper $contract_balance;
    }else{
        $invoice = get_invoice($contract_balance->{invoice_id},$client_contract->{id},$stime, $etime);
    }
    return ($contract_balance,$invoice);
}
sub get_invoice{
    my($invoice_id, $contract_id, $stime, $etime) = @_;
    my $invoice;
    if($invoice_id){
        $invoice = $dbh->selectrow_hashref('select * from invoices where id=?',undef, $invoice_id); 
    }else{
        $invoice = $dbh->selectrow_hashref('select * from invoices where contract_id=? and date(period_start)=? and date(period_end)=?',undef, $contract_id, $stime->ymd, $etime->ymd); 
    }
    if(!$invoice){
        my $serial_tmp = "tmp".time.int(rand(99999));
        $dbh->do('insert into invoices(contract_id,period_start,period_end,serial)values(?,?,?,?)', undef, $contract_id,$stime->ymd, $stime->ymd, $serial_tmp );
        $invoice->{id} = $dbh->last_insert_id(undef,'billing','invoices','id');
        @$invoice{qw/period_start period_end/} = ($stime,$etime);
        $invoice->{serial} = NGCP::Panel::Utils::Invoice::get_invoice_serial(undef,{invoice => $invoice});
        $dbh->do('update invoices set serial=? where id=?', undef, @$invoice{qw/serial id/} );
        $invoice = $dbh->selectrow_hashref('select * from invoices where id=?',undef, $invoice->{id});
    }
    if($invoice->{id} && !$invoice_id){
        $dbh->do('update contract_balances set invoice_id = ? where contract_id=? and start=? and end=?', undef, $invoice->{id},$contract_id, $stime->datetime, $etime->datetime );    
    }
    $invoice = {
        %$invoice,
        period_start => $stime,
        period_end   => $etime,
    };
    return $invoice;
}

sub get_email_template{
    my ($provider_contract) = @_;
    
    state $templates;
    state $template_default;
    if(!$templates){
        $templates = $dbh->selectall_hashref('select * from email_templates where name = ?','reseller_id',undef,"invoice_email");
        $template_default = $dbh->selectrow_hashref('select * from email_templates where name = ?',undef,"invoice_default_email");
    }
    my $res = ( $templates->{$provider_contract->{reseller_core_id}} or $template_default );
    return $res;
}

sub email{
#todo: repeat my old function based on templates and store into utils
    my($email_template,$provider_contact,$client_contact,$client_invoices,$transport_in) = @_;
    
    #print Dumper $client_invoices;
    my @invoice_ids = map {$_->{id}} @$client_invoices;

    $provider_contact->{id} //= '';
    $client_contact->{id} //= '';
    $client_contact->{email} //= '';
    print "send email for: provider_contact_id=".$provider_contact->{id}.";client_contact_id=".$client_contact->{id}."; client_contact->email=".$client_contact->{email}."; invoice_ids=".join(",",@invoice_ids).";\n";
    
    if(@$client_invoices < 1 ){
        return;
    }
    #state $transport_default;
    #$transport_default ||= Email::Sender::Transport::SMTP->new({
    #    sasl_username => 'ipeshinskaya',
    #
    #    #host => 'mail.sipwise.com',
    #    #port => 587,
    #    #sasl_password => '',
    #    #ssl => 0,
    #    
    #    host => 'smtp.googlemail.com',
    #    port => 465,
    #    ssl => 1,
    #    sasl_password => '',
    #});
    #
    #my $transport;
    #$transport_in and $transport = $transport_in;
    #$transport ||= $transport_default;
    
    #print Dumper $transport;
    
    $client_contact->{email} //= '';
    if(1 or $client_contact->{email}){
        my @attachments = map {
            my $invoice = $_;
            Email::MIME->create(
                attributes => {
                    filename     => "invoice_".$invoice->{serial}.".pdf",
                    content_type => "application/pdf",
                    encoding     => "base64",
                    #encoding     => "quoted-printable",
                    disposition  => "attachment",
                },
                #body => io( $pdf_ref )->all,
                body => $invoice->{data},
            );
        } @$client_invoices;
        
        my $tmpl_processed = NGCP::Panel::Utils::Email::process_template(undef,$email_template,{
            provider=>$provider_contact,
            client => $client_contact,
            invoices => $client_invoices,
        });
        #print Dumper $tmpl_processed;
        my $email = Email::MIME->create(
            header => [
                From    => $tmpl_processed->{from_email} || $provider_contact->{email},
                #To      => $tmpl_processed->{to} || $client_contact->{email},
                #To      => 'ipeshinskaya@gmail.com',
                To      => 'ipeshinskaya@sipwise.com',
                Subject => $tmpl_processed->{subject}, #todo: ask sales about subject
            ],
            parts => [
                @attachments,
                Email::MIME->create(
                    attributes => {
                        encoding     => "quoted-printable",
                        content_type => "text/plain",
                        charset      => "US-ASCII",
                    },
                    body_str => $tmpl_processed->{body},
                ),            
            ]
        );
        #sendmail($email, { transport => $transport });
        sendmail($email);
        print "Error sending email: $@" if $@;
        $dbh->do('update invoices set sent_date=now() where '.ify( ' id ',  @invoice_ids ), undef, @invoice_ids);
    }#we have correct "To"
}

sub ify{
    my $key = shift;
    return ( $#_  == 0 ) ? ' '.$key.' = ? ': ( ( $#_  > 0 ) ? ( ' '.$key. 'in('. ( '?,' x ( $#_ ) ) .'?) ' ) : ( wantarray ? () : '' ) );
}
sub ifp{
    my ($prefix, $value) = @_;
    return $value ? $prefix.$value : $value;
}
sub ifk{
    my ($key, $value) = @_;
    return $value ? $key : ();
}
sub v2a{
    my($value) = @_;
    return $value ? ($value): ();
}






