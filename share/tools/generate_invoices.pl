#!/usr/bin/perl -w
use lib '/root/VMHost/ngcp-panel/lib';
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
use Pod::Usage;
use HTML::Entities;

use NGCP::Panel::Utils::Invoice;

use Sipwise::Base;

use NGCP::Panel;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Invoice;
use NGCP::Panel::Utils::Email;

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

my $dbh = DBI->connect('dbi:mysql:billing;host=localhost', $dbuser, $dbpass, {mysql_enable_utf8 => 1})
    or die "failed to connect to billing DB\n";



my $opt = {};
Getopt::Long::GetOptions($opt, 'reseller_id:i@', 'client_contact_id:i@', 'client_contract_id:i@', 'stime:s', 'etime:s', 'send!','sendonly!','resend','regenerate!','prevmonth','force_unrated','help|?','man')
    or pod2usage(2);
print Dumper $opt;
pod2usage(1) if $opt->{help};
pod2usage(-exitval => 0, -verbose => 2) if $opt->{man};
    
my ($stime,$etime);
if($opt->{prevmonth}){
    $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' )->subtract(months => 1);
    $etime = $stime->clone->add( months => 1 )->subtract( seconds => 1 );
}else{
    $stime = $opt->{stime} 
        ? NGCP::Panel::Utils::DateTime::from_string($opt->{stime}) 
        : NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime = $opt->{etime} 
        ? NGCP::Panel::Utils::DateTime::from_string($opt->{etime}) 
        : $stime->clone->add( months => 1 )->subtract( seconds => 1 );
}
if( $opt->{client_contract_id} ){
    $opt->{reseller_id} = [$dbh->selectrow_array('select distinct contacts.reseller_id from contracts inner join contacts on contracts.contact_id=contacts.id '.ify(' where contracts.id', @{$opt->{client_contract_id}}),  undef, @{$opt->{client_contract_id}} )];
    $opt->{client_contact_id} = [$dbh->selectrow_array('select distinct contracts.contact_id from contracts '.ify(' where contracts.id', @{$opt->{client_contract_id}}),  undef, @{$opt->{client_contract_id}} )];
}
print Dumper $opt;
print "stime=$stime; etime=$etime;\n";

process_invoices();


sub process_invoices{
    #if(!$opt->{sendonly} && !check_unrated_calls()){
    #don't allow to send invoices too until admin directly request send for unrated
    if(!check_unrated_calls()){
        return;
    }
    my $invoices = {};

    foreach my $provider_contract( @{ get_providers_contracts() } ){
        
        print "reseller_id=".$provider_contract->{reseller_core_id}.";\n";
        
        my $provider_contact = get_provider_contact($provider_contract);

        foreach my $client_contact (@{ get_provider_clients_contacts($provider_contract) } ){

            print "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";\n";
            
            
            foreach my $client_contract (@{ get_client_contracts($client_contact) }){
                $logger->debug( "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";client_contract_id=".$client_contract->{id}.";\n" );
                
                $invoices->{$client_contract->{id}} ||= [];
                if(!$opt->{sendonly}){
                    print "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";contract_id=".$client_contract->{id}.";\n";

                    if( my $billing_profile = get_billing_profile($client_contract, $stime, $etime) ){
                        if(my $invoice = generate_invoice_data($provider_contract,$provider_contact,$client_contract,$client_contact,$billing_profile, $stime, $etime)){
                            $invoice->{data} = '';
                            push @{$invoices->{$client_contract->{id}}}, $invoice;
                        }
                    }else{#if billing profile
                        print "No billing profile;\n"
                    }
                }else{
                    $invoices->{$client_contract->{id}} = $dbh->selectall_arrayref('select invoices.id from invoices 
                    '.ifp(' where ',
                        join(' and ',
                            !$opt->{resend}?' invoices.sent_date is null ':(),
                            (ify(' invoices.contract_id ', (@{$opt->{client_contract_id}}, $client_contract->{id}) )),
                            (ifk(' date(invoices.period_start) >= ? ', v2a($stime->ymd))),
                            (ifk(' date(invoices.period_start) <= ? ', v2a($etime->ymd))),
                        )
                    ),  { Slice => {} }, @{$opt->{client_contract_id}}, v2a($client_contract->{id}), v2a($stime->ymd),v2a($etime->ymd) );
                }
                if($opt->{send} || $opt->{sendonly}){
                    my $email_template = get_email_template($provider_contract,$client_contract);
                    my $client_invoices = [ map {
                        my $invoice_full = get_invoice_by_id($_->{id});
                        preprocess_invoice_date($invoice_full,$stime,$etime);
                        $invoice_full;
                    } @{$invoices->{$client_contract->{id}}} ];
                    email($email_template, $provider_contact, $client_contact, $client_invoices );
                }
            }#foreach client contract
        }#foreach client contact
    }#foreach reseller
}

sub get_providers_contracts{
    return $dbh->selectall_arrayref('select contracts.*,resellers.id as reseller_core_id from resellers inner join contracts on resellers.contract_id=contracts.id where resellers.status != "terminated" '.ify(' and resellers.id ', @{$opt->{reseller_id}}),  { Slice => {} }, @{$opt->{reseller_id}} );
}
sub get_provider_contact{
    my($provider_contract) = @_;
    #todo: use selectall_hashref to don't query every time
    return $dbh->selectrow_hashref('select * from contacts where id=?', undef, $provider_contract->{contact_id} )
}
sub get_provider_clients_contacts{
    my($provider_contract) = @_;
    #according to /reseller/ajax_reseller_filter
    my $contacts = $dbh->selectall_arrayref('select contacts.* from contacts where reseller_id = ?'.ify(' and contacts.id', @{$opt->{client_contact_id}}),  { Slice => {} }, $provider_contract->{reseller_core_id}, @{$opt->{client_contact_id}} );
    #foreach (@$contacts){
    #    $_->{country_name} = country($_->{country});
    #}
    return $contacts;
}
sub get_client_contracts{
    my($client_contact) = @_;
    return $dbh->selectall_arrayref('select contracts.* from contracts where contracts.contact_id=? '.ify(' and contracts.id', @{$opt->{client_contract_id}}), { Slice => {} }, $client_contact->{id}, @{$opt->{client_contract_id}} );
}
sub get_billing_profile{
    my($client_contract, $stime, $etime) = @_;
    my $billing_profile;
    if(my $actual_billing_mapping = $dbh->selectrow_hashref('select * FROM billing_mappings 
        where contract_id = ? 
            and (billing_mappings.start_date <= ? OR billing_mappings.start_date is null)
            and (billing_mappings.end_date >= ? OR billing_mappings.end_date is null)
        order by billing_mappings.start_date desc, billing_mappings.id desc limit 1'
        , undef,  $client_contract->{id}, $etime->epoch, $stime->epoch)){

        #don't allow auto-generation for terminated contracts
        $billing_profile = $dbh->selectrow_hashref('select distinct billing_profiles.* 
        from billing_mappings
        inner join billing_profiles on billing_mappings.billing_profile_id=billing_profiles.id
        inner join contracts on contracts.id=billing_mappings.contract_id
        inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
        where billing_mappings.id=? 
            and contracts.status != "terminated"'

        , undef, $actual_billing_mapping->{id} 
        );
    }
    return $billing_profile;
}
sub get_invoice_data_raw{
    my($client_contract, $stime, $etime) = @_;
    my $invoice_details_calls = $dbh->selectall_arrayref('select cdr.*,from_unixtime(cdr.start_time) as start_time,bzh.zone, bzh.detail as zone_detail 
    from accounting.cdr 
    LEFT JOIN billing.billing_zones_history bzh ON bzh.bz_id = cdr.source_customer_billing_zone_id
    where
    cdr.source_user_id != "0"
    and cdr.call_status="ok" 
    and cdr.rating_status="ok"
    and cdr.source_account_id=?
    and cdr.start_time >= ?
    and cdr.start_time <= ?
    order by cdr.start_time '
    , { Slice => {} }
    , $client_contract->{id},$stime->epoch,$etime->epoch
    );
    my $invoice_details_zones = $dbh->selectall_arrayref('select SUM(cdr.source_customer_cost) AS customercost, COUNT(*) AS number, SUM(cdr.duration) AS duration,sum(cdr.source_customer_free_time) as free_time, bzh.zone
    from accounting.cdr 
    LEFT JOIN billing.billing_zones_history bzh ON bzh.bz_id = cdr.source_customer_billing_zone_id
    where
    cdr.source_user_id != "0"
    and cdr.call_status="ok" 
    and cdr.rating_status="ok"
    and cdr.source_account_id=?
    and cdr.start_time >= ?
    and cdr.start_time <= ?
    group by bzh.zone
    order by bzh.zone'
    , {Slice => {} }
    , $client_contract->{id},$stime->epoch,$etime->epoch
    );
    #/data for invoice generation
    
    #my $i = 1;
    #$invoice_details_calls = [map{[$i++,$_]} (@$invoice_details_calls) x 1];
    #$i = 1;
    #$invoice_details_zones = [map{[$i++,$_]} (@$invoice_details_zones) x 1];
    
    my $stash = {
        invoice_details_zones => $invoice_details_zones,
        invoice_details_calls => $invoice_details_calls,
    };
    return $stash;
}
sub check_unrated_calls{
    if($opt->{force_unrated}){
        return 1;
    }
    my $unrated_calls_info = $dbh->selectall_arrayref('select cdr.source_account_id, from_unixtime(min(cdr.start_time)) as start_time_min, from_unixtime(max(cdr.start_time)) as start_time_max, count(*) as calls_number
    from accounting.cdr 
    where
    cdr.source_user_id != "0"
    and cdr.call_status="ok" 
    and cdr.rating_status != "ok"
    and cdr.start_time >= ?
    and cdr.start_time <= ?
    group by cdr.source_account_id 
    order by cdr.source_account_id '
        , { Slice => {} }
        , $stime->epoch,$etime->epoch
    );
    if(@$unrated_calls_info){
        my $msg = "\n\n\n\n".'There are '.@$unrated_calls_info.' customers which have unrated calls in the '.$stime->ymd.' - '.$etime->ymd.' period. Run '.__FILE__.' script with option --force_unrated to generate invoices anyway.'."\n\n\n\n";
        my $info = join("\n",map {"Customer: ".sprintf("%5d",$_->{source_account_id})."; Unrated calls: ".sprintf("%5d",$_->{calls_number})."; Period: $_->{start_time_min} - $_->{start_time_max};"} @$unrated_calls_info);
        print $msg;
        print $info;
        my $email = Email::MIME->create(
            header => [
                From    => 'invoice_generator@sipwise.com',
                To      => $opt->{warning_email} || 'root@localhost',
                #To      => 'ipeshinskaya@sipwise.com',
                Subject => 'Invoice generator warning',
            ],
            parts => [
                Email::MIME->create(
                    attributes => {
                        encoding     => "quoted-printable",
                        content_type => "text/plain",
                        charset      => "US-ASCII",
                    },
                    body_str => $msg.$info,
                ),            
            ]
        );
        #sendmail($email, { transport => $transport });
        sendmail($email);
        return 0;
    }
    return 1;
}
sub generate_invoice_data{
    my($provider_contract,$provider_contact,$client_contract,$client_contact,$billing_profile, $stime, $etime) = @_;
    
    state ($t,$svg_default);
    if(!$t){
        $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();        
        $svg_default = $t->context->insert('invoice/default/invoice_template_svg.tt');
        #NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$svg_default);
    }
    my $svg = $dbh->selectrow_array('select data from invoice_templates where is_active = 1 and type = "svg" and reseller_id=?',undef,$provider_contract->{reseller_core_id});#
    utf8::decode($svg);
    if($svg){
        #NGCP::Panel::Utils::InvoiceTemplate::preprocess_svg(\$svg);
    }else{
        $svg = $svg_default;
        print "No saved active template - no invoice;\n";
        return;
    }

    my ($contract_balance,$invoice)=({},{});
    ($contract_balance,$invoice) = get_contract_balance($client_contract,$billing_profile,$contract_balance,$invoice,$stime,$etime);
    #print Dumper $contract_balance;
    
    $client_contact->{country} = country($client_contact->{country} || '');
    foreach(keys %$client_contact){
        $client_contact->{$_} = encode_entities($client_contact->{$_}, '<>&"');
    }
    $provider_contact->{country} = country($provider_contact->{country} || '');
    foreach(keys %$provider_contact){
        $provider_contact->{$_} = encode_entities($provider_contact->{$_}, '<>&"');
    }
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
    $invoice->{data} = '';
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
        #print Dumper $contract_balance;
    }else{
        $invoice = get_invoice($contract_balance->{invoice_id},$client_contract->{id},$stime, $etime);
    }
    return ($contract_balance,$invoice);
}
sub get_invoice{
    my($invoice_id, $contract_id, $stime, $etime) = @_;
    my $invoice;
    if($opt->{regenerate}){
        if($invoice_id){
            $invoice = $dbh->selectrow_hashref('select * from invoices where id=?',undef, $invoice_id); 
        }else{
            $invoice = $dbh->selectrow_hashref('select * from invoices where contract_id=? and date(period_start)=? and date(period_end)=?',undef, $contract_id, $stime->ymd, $etime->ymd); 
        }
    }
    if(!$invoice){
        my $serial_tmp = "tmp".time.int(rand(99999));
        $dbh->do('insert into invoices(contract_id,period_start,period_end,serial)values(?,?,?,?)', undef, $contract_id,$stime->ymd.' '.$stime->hms, $etime->ymd.' '.$etime->hms, $serial_tmp );
        $invoice->{id} = $dbh->last_insert_id(undef,'billing','invoices','id');
        #are necessary here for serial generation
        @$invoice{qw/period_start period_end/} = ($stime,$etime);
        $invoice->{serial} = NGCP::Panel::Utils::Invoice::get_invoice_serial(undef,{invoice => $invoice});
        $dbh->do('update invoices set serial=? where id=?', undef, @$invoice{qw/serial id/} );
        $invoice = $dbh->selectrow_hashref('select * from invoices where id=?',undef, $invoice->{id});
    }
    if($invoice->{id} && !$invoice_id){
        $dbh->do('update contract_balances set invoice_id = ? where contract_id=? and start=? and end=?', undef, $invoice->{id},$contract_id, $stime->datetime, $etime->datetime );    
    }
    preprocess_invoice_date($invoice, $stime, $etime);
    return $invoice;
}
sub preprocess_invoice_date{
    my ($invoice_ref, $stime, $etime) =@_;
    #obj value will be used in email
    @$invoice_ref{qw/period_start period_start_obj period_end period_end_obj/} = ( $stime, $stime, $etime,$etime);
}
sub get_invoice_by_id{
    my ($invoice_id) =@_;
    $dbh->selectrow_hashref('select * from invoices where id=?',undef,$invoice_id);
}

sub get_email_template{
    my ($provider_contract,$client_contract) = @_;
    
    #use memcache?
    state $templates;
    state $template_default;
    if(!$templates){
        $templates = $dbh->selectall_hashref('select * from email_templates where name = ?','reseller_id',undef,"invoice_email");
        $template_default = $dbh->selectrow_hashref('select * from email_templates where name = ?',undef,"invoice_default_email");
    }
    my $res = {};
    if($client_contract->{invoice_email_template_id}){
        $res = $dbh->selectrow_hashref('select * from email_templates where id = ?',undef,$client_contract->{invoice_email_template_id});
    }else{
        $res = ( $templates->{$provider_contract->{reseller_core_id}} or $template_default );
    }
    foreach(qw/body subject from_email/){
        utf8::decode($res->{$_});
    }
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
    
    #one-by-one
    $client_invoices = [$client_invoices->[0]];
    @invoice_ids = map {$_->{id}} @$client_invoices;

    $client_contact->{email} //= '';
    if($client_contact->{email}){
        my @attachments = map {
            my $invoice = $_;
            Email::MIME->create(
                attributes => {
                    filename     => "invoice_".$invoice->{serial}.".pdf",
                    content_type => "application/pdf",
                    encoding     => "base64",
                    disposition  => "attachment",
                },
                body => $invoice->{data},
            );
        } @$client_invoices;
        my $invoice = $client_invoices->[0];
        foreach (qw/period_start period_end/){
            $invoice->{$_.'_obj'} = NGCP::Panel::Utils::DateTime::from_string($invoice->{$_}) unless $invoice->{$_.'_obj'};
        }
        foreach (qw/month year/){
            $invoice->{$_} = $invoice->{period_start_obj}->$_ unless $invoice->{$_};
        }
        
        my $tmpl_processed = NGCP::Panel::Utils::Email::process_template(undef,$email_template,{
            provider => $provider_contact,
            client   => $client_contact,
            invoice  => $invoice,
        });
        #print Dumper $tmpl_processed;
        my $email = Email::MIME->create(
            header => [
                From    => $tmpl_processed->{from_email} || $provider_contact->{email},
                To      => $tmpl_processed->{to} || $client_contact->{email},
                #To      => 'ipeshinskaya@gmail.com',
                #To      => 'ipeshinskaya@sipwise.com',
                Subject => $tmpl_processed->{subject}, #todo: ask sales about subject
            ],
            parts => [
                @attachments,
                Email::MIME->create(
                    attributes => {
                        encoding     => "quoted-printable",
                        content_type => "text/plain",
                        charset      => "UTF-8",
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


 __END__

=head1 generate_invoices.pl

Script to generate invoices and/or send them via email to customers.
location: /usr/share/ngcp-panel/tools/generate_invoices.pl

=head1 OPTIONS

=item --reseller_id=ID1[,IDn]        

Generate invoices only for specified resellers customers

=item --client_contact_id=ID1[,IDn]  

Generate invoices only for customers, defined by their contact IDs           

=item --client_contract_id=ID1[,IDn] 

Generate invoices only for customers, defined by their contract IDs          

=item --prevmonth             
       
Generate invoices for calls within period of previous month.         

=item --stime="YYYY-mm-DD HH:MM:SS"  

Generate invoices for calls within period, started from option value. Call start_time will be bigger then option value. Default is start second of current month.         

=item --etime="YYYY-mm-DD HH:MM:SS"  

Generate invoices for calls within period, ended by option value. Call start_time will be less then option value. Default is last second of current month, or last second of month period, started from stime value.         

=item --send                         

Invoices will be sent to customers emails just after generation. Default is false.         

=item --sendonly                     

Makes to send invoices, which weren't sent yet, to customers. Other options: resellers, customers, period specification will be considered. Should be used to send invoices to customers monthly, after generation. Default is false.      
    

=item --force_unrated

Generate invoices despite unrated calls existance in the period.
=head1 SAMPLES

=item To generate invoices for current month:

perl /usr/share/ngcp-panel/tools/generate_invoice.pl

=item To generate invoices for previous month:

perl /usr/share/ngcp-panel/tools/generate_invoice.pl --prevmonth

Crontab example:
#m h d M dw
5 5 1 * * perl /usr/share/ngcp-panel-tools/generate_invoice.pl --prevmonth 2>&1 >/dev/null

=item To send invoices which weren't sent yet

To get invoices, which weren't sent yet, period value will be considered too. It means that started from cron to send invoices generated for previous month, script should get "--prevmonth" option.

perl /usr/share/ngcp-panel/tools/generate_invoice.pl --sendonly --prevmonth

Crontab example:
#m h d M dw
5 */2 * * * perl /usr/share/ngcp-panel-tools/generate_invoice.pl --sendonly --prevmonth 2>&1 >/dev/null

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<generate_invoices.pl> Script to generate invoices and/or send them via email to customers..

=cut



