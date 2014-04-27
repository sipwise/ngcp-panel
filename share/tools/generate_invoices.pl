#!/usr/bin/perl -w
use lib '/media/sf_/usr/share/VMHost/ngcp-panel/lib';
use strict;

use DBI;
use Data::Dumper;
use NGCP::Panel::Utils::DateTime;
use DateTime::TimeZone;
#use Net::Domain qw(hostfqdn);
#use LWP::UserAgent;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::InvoiceTemplate;
use NGCP::Panel;
use NGCP::Panel::View::SVG;
use Test::MockObject;
use Sipwise::Base;
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

#my ($ua, $req, $res);
#use LWP::UserAgent;
#use HTTP::Request;
#$ua = LWP::UserAgent->new;
#$req = HTTP::Request->new('OPTIONS', 'https://192.168.56.7:1444/invoice/3/template');
##$res = $ua->request($req);
#my $controller = NGCP::Panel->controller('Invoice'); 
#my $c = NGCP::Panel->prepare($ua); 
##$c->request->param->{tt_id} = 126; 
##$c->request->method( 'POST' );
##$c->request->uri( 'https://192.168.56.7:1444/invoice/3/template');
#die();
my $dbh = DBI->connect('dbi:mysql:billing;host=localhost', $dbuser, $dbpass)
	or die "failed to connect to billing DB\n";


my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
my $etime_plus = $stime->clone->add( months => 1 );
my $etime = $etime_plus->clone->subtract( seconds => 1 );

my $c_mock = Test::MockObject->new();
$c_mock->set_false(qw/debug/);
my $view = NGCP::Panel::View::SVG->new($c_mock,{});
my $svg_default = $view->getTemplateContent(undef,'invoice/invoice_template_svg.tt');
NGCP::Panel::Utils::InvoiceTemplate::preprocessInvoiceTemplateSvg( {no_fake_data => 1}, \$svg_default);
#print $etime->ymd;

foreach my $provider_contract( @{$dbh->selectall_arrayref('select contracts.*,resellers.id as reseller_core_id from resellers inner join contracts on resellers.contract_id=contracts.id where resellers.status != "terminated"',  { Slice => {} } ) } ){
    my $provider_contact = $dbh->selectrow_hashref('select * from contacts where id=?', undef, $provider_contract->{contact_id} );

    foreach my $client_contact (@{ $dbh->selectall_arrayref('select contacts.* from contacts where reseller_id = ?',  { Slice => {} }, $provider_contract->{reseller_core_id} ) } ){
        my $client_contract = $dbh->selectrow_hashref('select contracts.* from contracts where contracts.contact_id=? ', undef, $client_contact->{id} );

        if( my $billing_profile = $dbh->selectrow_hashref('select billing_profiles.* 
    from billing_mappings
    inner join billing_profiles on billing_mappings.billing_profile_id=billing_profiles.id
    inner join contracts on contracts.id=billing_mappings.contract_id
    inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
    where 
        contracts.status != "terminated"
        and contracts.contact_id=?
        and (billing_mappings.start_date <= ? OR billing_mappings.start_date IS NULL)
        and (billing_mappings.end_date >= ? OR billing_mappings.end_date IS NULL)'
, undef, $client_contract->{id}, $etime->epoch, $stime->epoch 
) ){
            my $invoice;
            if(!(my $contract_balance = $dbh->selectrow_hashref('select * from contract_balances where contract_id=? and date(start)=? and date(end)=?',undef,$client_contract->{id},$stime->ymd,$etime->ymd))){

                
                @$contract_balance{qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/} = NGCP::Panel::Utils::Contract::get_contract_balance_values(
                    %$billing_profile,
                    stime => $stime,
                    etime => $etime->datetime,
                );
                $dbh->do('insert into contract_balances(contract_id,cash_balance,cash_balance_interval,free_time_balance,free_time_balance_interval,start,end,invoice_id)values(?,?,?,?,?,?,?,?)',undef,$client_contract->{id},@$contract_balance{qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/},$stime->datetime, $etime->datetime,undef );
                $invoice = create_invoice($client_contract->{id},$stime, $etime);
                $contract_balance = $dbh->selectrow_hashref('select * from contract_balances where id=?',undef,$dbh->last_insert_id(undef,'billing','contract_balances','id'));
            }else{
                if(!$contract_balance->{invoice_id} || !( $invoice = $dbh->selectrow_hashref('select * from invoices where id=?',undef,$contract_balance->{invoice_id} ))){
                    $invoice = create_invoice($client_contract->{id},$stime, $etime);
                }
            }
            my $invoice_details_calls = $dbh->selectall_arrayref('select cdr.*,bzh.zone, bzh.detail as zone_detail 
    from accounting.cdr 
        LEFT JOIN billing.billing_zones_history bzh ON bzh.id = cdr.source_customer_billing_zone_id
    where
        cdr.source_user_id != 0
        and cdr.call_status="ok" 
--        and cdr.source_account_id=?
--        and cdr.start_time >= ?
--        and cdr.start_time <= ?
        order by cdr.start_time
        limit 25'
        , { Slice => {} }
#, $client_contract->{id},$stime->epoch,$etime->epoch
);
            my $invoice_details_zones = $dbh->selectall_arrayref('select SUM(cdr.source_customer_cost) AS cost, COUNT(*) AS number, SUM(cdr.duration) AS duration,sum(cdr.source_customer_free_time) as free_time, bzh.zone
    from accounting.cdr 
        LEFT JOIN billing.billing_zones_history bzh ON bzh.id = cdr.source_customer_billing_zone_id
    where
        cdr.source_user_id != 0
        and cdr.call_status="ok" 
--        and cdr.source_account_id=?
--        and cdr.start_time >= ?
--        and cdr.start_time <= ?
        group by bzh.zone
        order by bzh.zone'
        , {Slice => {} }
#, $client_contract->{id},$stime->epoch,$etime->epoch
        
            );
            my $i = 1;
            $invoice_details_calls = [map{[$i++,$_]} (@$invoice_details_calls) x 1];
            $i = 1;
            $invoice_details_zones = [map{[$i++,$_]} (@$invoice_details_zones) x 1];
            my ($in, $out);
            #tt_id used only as part in temporary directory
            $in = {
                no_fake_data   => 1,
                provider_id    => $provider_contract->{reseller_core_id},
                tt_type        => 'svg',
                tt_sourcestate => 'saved',
                tt_id          => 1,
            };
            $out = {
                tt_id => 1,
            };
            my $stash = {
                provider => $provider_contact,
                client   => $client_contact,
                invoice  => $invoice,
                invoice_details_zones => $invoice_details_zones,
                invoice_details_calls => $invoice_details_calls,
            };
            my $svg = $dbh->selectrow_array('select base64_saved from invoice_templates where is_active = 1 and type = "svg" and reseller_id=?',undef,$provider_contract->{reseller_core_id});
            if(!$svg){
                $svg = $svg_default;
                #print "svg=$svg;";
            }else{
                NGCP::Panel::Utils::InvoiceTemplate::preprocessInvoiceTemplateSvg($in,\$svg);
            }
            $svg = $view->getTemplateProcessed($c_mock,\$svg, $stash );
            NGCP::Panel::Utils::InvoiceTemplate::convertSvg2Pdf(undef,\$svg,$in,$out);
            binmode(STDOUT);
            print $out->{tt_string_pdf};
            die;
            
            #my $result = $c->forward($controller, 'invoice_templaet', [] ); 
            
            #$req = HTTP::Request->new('OPTIONS', $uri.'/invoice/'..'/');
            #$res = $ua->request($req);
        }
    }
}
sub create_invoice{
    my($contract_id, $stime, $etime) = @_;
    #my $invoice_serial = $dbh->selectrow_array('select max(invoices.serial) from invoices inner join contract_balances on invoices.id=contract_balances.invoice_id where contract_balances.contract_id=?',undef,$contract_id );    
    my $invoice_serial = $dbh->selectrow_array('select max(invoices.serial) from invoices'); 
    $invoice_serial += 1;
    $dbh->do('insert into invoices(year,month,serial)values(?,?,?)', undef, $stime->year, $stime->month,$invoice_serial );
    my $invoice_id = $dbh->last_insert_id(undef,'billing','invoices','id');
    $dbh->do('update contract_balances set invoice_id = ? where contract_id=? and start=? and end=?', undef, $invoice_id,$contract_id, $stime->datetime, $etime->datetime );
    return $dbh->selectrow_hashref('select * from invoices where id=?',undef, $invoice_id);    
}







# OPTIONS tests