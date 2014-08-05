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
use Pod::Usage;
use Log::Log4perl;

use Sipwise::Base;

use NGCP::Panel;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel::Utils::Invoice;
use NGCP::Panel::Utils::Email;

my $opt = {};
Log::Log4perl::init('/etc/ngcp-ossbss/logging.conf');
my $logger = Log::Log4perl->get_logger('NGCP::Panel');

{
    my $config_file = "/etc/ngcp-invoice-gen/invoice-gen.conf";
    if(-e $config_file){
        open CONFIG, "$config_file" or die "Program stopping, couldn't open the configuration file '$config_file'.\n";

        #can try CONFIG::Hash, Env::Sourced
        while (<CONFIG>) {
            chomp;                  # no newline
            s/#.*//;                # no comments
            s/^\s+//;               # no leading white
            s/\s+$//;               # no trailing white
            next unless length;     # anything left?
            my ($var, $value) = split(/\s*=\s*/, $_, 2);
            $opt->{lc $var} = $value;
        }
        close CONFIG;
    }
}

    
my $dbh;
{
    my ($dbcfg);
    foreach(qw/dbuser dbpass dbdb dbhost dbport/){
        $opt->{$_} and $dbcfg->{$_} = $opt->{$_};
    }
    if((!$dbcfg->{dbuser}) || (!$dbcfg->{dbpass})){
        my $mfile = '/etc/mysql/sipwise.cnf';
        if(-f $mfile) {
            open my $fh, "<", $mfile
                or die "failed to open '$mfile': $!\n";
            $_ = <$fh>; chomp;
            s/^SIPWISE_DB_PASSWORD='(.+)'$/$1/;
            $dbcfg->{dbuser} = 'sipwise'; 
            $dbcfg->{dbpass} = $_;
        } else {
            $dbcfg->{dbuser} = 'root';
            $dbcfg->{dbpass} = '';
        }
    }
    $dbcfg->{dbdb} //= 'billing';
    $dbcfg->{dbhost} //= 'localhost';
    $dbh = DBI->connect('dbi:mysql:'.$dbcfg->{dbdb}.';host='.$dbcfg->{dbhost}, $dbcfg->{dbuser}, $dbcfg->{dbpass}, {mysql_enable_utf8 => 1})
        or die "failed to connect to billing DB\n";
}

Getopt::Long::GetOptions($opt, 
    'reseller_id:i@', 
    'client_contact_id:i@', 
    'client_contract_id:i@', 
    'stime:s', 
    'etime:s', 
    'prevmonth',
    'sendonly',
    'send',
    'resend',
    'regenerate',
    'allow_terminated',
    'backward_is_active',
    'update_contract_balance',
    'update_contract_balance_nonzero',
    'force_unrated',
    'help|?',
    'man'
) or pod2usage(2);
$logger->debug( Dumper $opt );
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
$logger->debug( Dumper $opt );
$logger->debug( "stime=$stime; etime=$etime;\n" );

process_invoices();


sub process_invoices{
    if(!check_unrated_calls()){
        return;
    }
    my $invoices = {};

    foreach my $provider_contract( @{ get_providers_contracts() } ){
        
        $logger->debug( "reseller_id=".$provider_contract->{reseller_core_id}.";\n" );
        
        my $provider_contact = get_provider_contact($provider_contract);

        foreach my $client_contact (@{ get_provider_clients_contacts($provider_contract) } ){

            $logger->debug( "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";\n" );
            
            
            foreach my $client_contract (@{ get_client_contracts($client_contact, $stime, $etime) }){
                    
                $invoices->{$client_contract->{id}} ||= [];
                if(!$opt->{sendonly}){
                    $logger->debug( "reseller_id=".$provider_contract->{reseller_core_id}.";contact_id=".$client_contact->{id}.";contract_id=".$client_contract->{id}.";\n");

                    if( my $billing_profile = get_billing_profile($client_contract, $stime, $etime) ){
                        if(my $invoice = generate_invoice_data($provider_contract,$provider_contact,$client_contract,$client_contact,$billing_profile, $stime, $etime)){
                            push @{$invoices->{$client_contract->{id}}}, $invoice;
                        }
                    }else{#if billing profile
                        $logger->debug( "No billing profile;\n");
                    }
                }else{
                    $invoices->{$client_contract->{id}} = $dbh->selectall_arrayref('select invoices.* from invoices where invoices.generator="auto" 
                    '.ifp(' and ',
                        join(' and ',
                            !$opt->{resend}?' invoices.sent_date is null ':(),
                            (ify(' invoices.contract_id ', (@{$opt->{client_contract_id}}, $client_contract->{id}) )),
                            (ifk(' date(invoices.period_start) >= ? ', v2a($stime ? $stime->ymd : undef))),
                            (ifk(' date(invoices.period_start) <= ? ', v2a($etime ? $etime->ymd : undef))),
                        )
                    ),  { Slice => {} }, @{$opt->{client_contract_id}}, v2a($client_contract->{id}), v2a($stime->ymd),v2a($etime->ymd) );
                }
                if($opt->{send} || $opt->{sendonly}){
                    my $email_template = get_email_template($provider_contract,$client_contract);
                    email($email_template, $provider_contact, $client_contact, $invoices->{$client_contract->{id}} );
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
    my($client_contact,$stime,$etime) = @_;
    return $dbh->selectall_arrayref('select contracts.* 
    from contracts 
    left join invoices on contracts.id=invoices.contract_id and invoices.generator="auto" '
        .ifp(' and ',
            join(' and ',
                (ifk(' date(invoices.period_start) >= ? ', v2a($stime ? $stime->ymd : undef))),
                (ifk(' date(invoices.period_start) <= ? ', v2a($etime ? $etime->ymd : undef ))),
            )
        )
        .' where contracts.contact_id=? '
        .( ( !$opt->{allow_terminated} ) ? ' and contracts.status != "terminated" ' : '' )
        .ify(' and contracts.id ', @{$opt->{client_contract_id}})
        .(( !$opt->{regenerate} && !$opt->{sendonly} )?' and invoices.contract_id is null ': '' )
        .' group by contracts.id ', 
        { Slice => {} }, 
        v2a($stime->ymd),v2a($etime->ymd),$client_contact->{id}, @{$opt->{client_contract_id}} 
    );
}

sub get_billing_profile{
    my($client_contract, $stime, $etime) = @_;
    #don't allow auto-generation for terminated contracts
    $dbh->selectrow_hashref('select distinct billing_profiles.* 
        from billing_mappings
        inner join billing_profiles on billing_mappings.billing_profile_id=billing_profiles.id
        inner join contracts on contracts.id=billing_mappings.contract_id
        inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
        where 
            contracts.id = ? '
            .( ( !$opt->{allow_terminated} ) ? ' and contracts.status != "terminated" ':'' )
            .' and (billing_mappings.start_date <= ? OR billing_mappings.start_date IS NULL)
               and (billing_mappings.end_date >= ? OR billing_mappings.end_date IS NULL)'
    , undef, $client_contract->{id}, $etime->epoch, $stime->epoch 
    );
}
sub get_invoice_data_raw{
    my($client_contract, $stime, $etime, $opt_local) = @_;
    $opt_local //= {};
    my ($invoice_details_calls,$invoice_details_zones);
    if(!$opt_local->{count_contract_balance}){
        $invoice_details_calls = $dbh->selectall_arrayref('select cdr.*,from_unixtime(cdr.start_time) as start_time,bzh.zone, bzh.detail as zone_detail 
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
    }
    $invoice_details_zones = $dbh->selectall_arrayref('select SUM(cdr.source_customer_cost) AS customercost, COUNT(*) AS number, SUM(cdr.duration) AS duration,sum(cdr.source_customer_free_time) as free_time '
    .(!$opt_local->{count_contract_balance}?', bzh.zone':'')
    .'
    from accounting.cdr '
    .(!$opt_local->{count_contract_balance}?'LEFT JOIN billing.billing_zones_history bzh ON bzh.bz_id = cdr.source_customer_billing_zone_id ':'')
    .' where
    cdr.source_user_id != "0"
    and cdr.call_status="ok" 
    and cdr.rating_status="ok"
    and cdr.source_account_id=?
    and cdr.start_time >= ?
    and cdr.start_time <= ?'
    .(!$opt_local->{count_contract_balance}?'group by bzh.zone
    order by bzh.zone':'')
    , {Slice => {} }
    , $client_contract->{id},$stime->epoch,$etime->epoch
    );
    #/data for invoice generation
    
    #my $i = 1;
    #$invoice_details_calls = [map{[$i++,$_]} (@$invoice_details_calls) x 1];
    #$i = 1;
    #$invoice_details_zones = [map{[$i++,$_]} (@$invoice_details_zones) x 1];
    my $stash;
    if($opt_local->{count_contract_balance}){
        $stash = $invoice_details_zones->[0];
    }else{
        $stash = {
            invoice_details_zones => $invoice_details_zones,
            invoice_details_calls => $invoice_details_calls,
        };
    }
    return $stash;
}
sub check_unrated_calls{
    if($opt->{force_unrated}){
        return;
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
        $logger->debug($msg);
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
    
    state($t);
    if(!$t){
        $t = NGCP::Panel::Utils::InvoiceTemplate::get_tt();
    }
    
    my $svg;
    if(!(my $svg_ref = get_invoice_template($t, $provider_contract,$client_contract))){
        return;
    }else{
        $svg = $$svg_ref;
    }
    
    my ($contract_balance,$invoice)=({},{});
    my($contract_balance_data) = get_invoice_data_raw($client_contract, $stime, $etime,{count_contract_balance => 1});
    ($contract_balance,$invoice) = get_contract_balance($client_contract,$billing_profile,$contract_balance,$contract_balance_data,$invoice,$stime,$etime);
    #$logger->debug( Dumper $contract_balance );
    NGCP::Panel::Utils::Invoice::prepare_contact_data($client_contact);
    NGCP::Panel::Utils::Invoice::prepare_contact_data($provider_contact);
    #TODO: if not a full month, calculate fraction?
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
    print Dumper $invoice_data;
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
    $logger->debug( "generated data for invoice.id=".$invoice->{id}."; invoice.serial=".$invoice->{serial}.";\n" );
    $invoice->{data} = $pdf;
    #set sent_date to null after each data regeneration
    $dbh->do('update invoices set sent_date=?,data=?,amount_net=?,amount_vat=?,amount_total=? where id=?',undef,undef,@$invoice{qw/data amount_net amount_vat amount_total id/});    
    return $invoice;
}

sub get_contract_balance{
    my($client_contract,$billing_profile,$contract_balance,$contract_balance_data,$invoice,$stime,$etime) = @_;
    if(!($contract_balance = $dbh->selectrow_hashref('select * from contract_balances where contract_id=? and date(start)=? and date(end)=?',undef,$client_contract->{id},$stime->ymd,$etime->ymd))){
        @$contract_balance{qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/} = NGCP::Panel::Utils::Contract::get_contract_balance_values(
            %$billing_profile,
            stime => $stime,
            etime => $etime,
        );
        $contract_balance->{cash_balance_interval} ||= $contract_balance_data->{customercost};
        $contract_balance->{free_time_balance_interval} ||= $contract_balance_data->{free_time};
        $dbh->do('insert into contract_balances(contract_id,cash_balance,cash_balance_interval,free_time_balance,free_time_balance_interval,start,end,invoice_id)values(?,?,?,?,?,?,?,?)',undef,$client_contract->{id},@$contract_balance{qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/},$stime->datetime, $etime->datetime,undef );
        $invoice = get_invoice(undef, $client_contract->{id},$stime, $etime);
        #my $contract_balance_id = $dbh->last_insert_id(undef,'billing','contract_balances','id');
        #$logger->debug( "contract_balance_id=$contract_balance_id;\n");
        #$contract_balance = $dbh->selectrow_hashref('select * from contract_balances where id=?',undef,);  
        $contract_balance = $dbh->selectrow_hashref('select * from contract_balances where contract_id=? and date(start)=? and date(end)=?',undef,$client_contract->{id},$stime->ymd,$etime->ymd);
        #$logger->debug( Dumper $contract_balance );
    }else{
        if($opt->{update_contract_balance} && $contract_balance_data){
            my @sql_update = ();
            my @sql_update_params = ();
            $contract_balance->{cash_balance_interval} //= 0;
            $contract_balance_data->{customercost} //= 0;
#            print Dumper $contract_balance_data;
            if(($contract_balance->{cash_balance_interval} != $contract_balance_data->{customercost})
                && ($opt->{update_contract_balance_nonzero} 
                    || 
                    ( $contract_balance_data->{customercost} > 0 
                    && !$contract_balance->{cash_balance_interval}
                    )
                )
            ){
                push @sql_update,'cash_balance_interval=?';
                push @sql_update_params,$contract_balance_data->{customercost};
            }
            $contract_balance->{free_time_balance_interval} //= 0;
            $contract_balance_data->{free_time} //= 0;
            if($contract_balance->{free_time_balance_interval} != $contract_balance_data->{free_time}
                && ($opt->{update_contract_balance_nonzero} 
                    || 
                    ( $contract_balance_data->{free_time} > 0 
                    && !$contract_balance->{free_time_balance_interval}
                    )
                )
            ){
                push @sql_update,'free_time_balance_interval=?';
                push @sql_update_params,$contract_balance_data->{free_time};
            }
            if(my $sql_update = join(',',@sql_update)){
                $dbh->do('update contract_balances set '.$sql_update.' where contract_id=? and date(start)=? and date(end)=?',undef,@sql_update_params,$client_contract->{id},$stime->ymd,$etime->ymd);
            }
        }
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
            $invoice = $dbh->selectrow_hashref('select * from invoices where contract_id=? and date(period_start)=? and date(period_end)=? and invoices.generator="auto" ',undef, $contract_id, $stime->ymd, $etime->ymd); 
        }
    }
    if(!$invoice){
        my $serial_tmp = "tmp".time.int(rand(99999));
        $dbh->do('insert into invoices(contract_id,period_start,period_end,serial,generator)values(?,?,?,?,?)', undef, $contract_id, $stime->ymd.' '.$stime->hms, $etime->ymd.' '.$etime->hms, $serial_tmp, 'auto' );
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
    #obj value will be used in email
    $invoice = {
        %$invoice,
        period_start     => $stime,
        period_start_obj => $stime,
        period_end       => $etime,
        period_end_obj   => $etime,
    };
    return $invoice;
}

sub get_invoice_template{
    my($t, $provider_contract, $client_contract ) = @_;
    
    my $svg;
    if($opt->{backward_is_active}){
        $svg = $dbh->selectrow_array('select data from invoice_templates where type="svg" and is_active=1 and reseller_id=?',undef,$provider_contract->{reseller_core_id});
    }else{
        $svg = $dbh->selectrow_array('select data from invoice_templates where id=?',undef,$client_contract->{invoice_template_id});
    }
    
    if(!$svg){
        $logger->debug( "No saved template for customer - no invoice;\n");
        return ;
    }
    utf8::decode($svg);
    return \$svg;
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
    return $res;
}

sub email{
#todo: repeat my old function based on templates and store into utils
    my($email_template,$provider_contact,$client_contact,$client_invoices,$transport_in) = @_;
    
    #$logger->debug(Dumper $client_invoices);
    my @invoice_ids = map {$_->{id}} @$client_invoices;

    $provider_contact->{id} //= '';
    $client_contact->{id} //= '';
    $client_contact->{email} //= '';
    $logger->debug("send email for: provider_contact_id=".$provider_contact->{id}.";client_contact_id=".$client_contact->{id}."; client_contact->email=".$client_contact->{email}."; invoice_ids=".join(",",@invoice_ids).";\n");
    
    
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
        #$logger->debug(Dumper $tmpl_processed);
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
                        charset      => "US-ASCII",
                    },
                    body_str => $tmpl_processed->{body},
                ),            
            ]
        );
        #sendmail($email, { transport => $transport });
        sendmail($email);
        $logger->error("Error sending email: $@") if $@;
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

=item --allow_terminated                     

Generates invoices for terminated contracts too. 

=item --force_unrated

Generate invoices despite unrated calls existance in the period.

=item --backward_is_active

Use old is_active logic of invoice_template selection. For internal use.

=item --update_contract_balance

For internal use. Update contract_balances *_balance_interval fields with values according to invoice lists.

=item --update_contract_balance_nonzero

For internal use. Configuration for option --update_contract_balance. Allows update contract_balances.[cash|free_time]_balance_interval fields

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

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<generate_invoices.pl> Script to generate invoices and/or send them via email to customers..

=cut



