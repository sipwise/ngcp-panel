
use strict;
use warnings;
use threads qw();
use threads::shared qw();

#use Sipwise::Base; #causes segfault when creating threads..
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
#use Storable qw();
use Time::Fake;
use DateTime::Format::Strptime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Storable;
use Text::Table;
use Text::Wrap;
$Text::Wrap::columns = 58;

use JSON::PP;
use LWP::Debug;

BEGIN {
    unshift(@INC,'../lib');
}
use NGCP::Panel::Utils::DateTime qw();
use NGCP::Panel::Utils::ProfilePackages qw();

my $is_local_env = 0;
my $enable_profile_packages = NGCP::Panel::Utils::ProfilePackages::ENABLE_PROFILE_PACKAGES;

use Config::General;
my $catalyst_config;
if ($is_local_env) {
    $catalyst_config = Config::General->new("../ngcp_panel.conf");
} else {
    #taken 1:1 from /lib/NGCP/Panel.pm
    my $panel_config;
    for my $path(qw#/etc/ngcp-panel/ngcp_panel.conf etc/ngcp_panel.conf ngcp_panel.conf#) {
        if(-f $path) {
            $panel_config = $path;
            last;
        }
    }
    $panel_config //= 'ngcp_panel.conf';
    $catalyst_config = Config::General->new($panel_config);   
}
my %config = $catalyst_config->getall();

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

if ($is_local_env) {
    $ua->ssl_opts(
        verify_hostname => 0,
    );
    $ua->credentials("127.0.0.1:4443", "api_admin_http", 'administrator', 'administrator');
    #$ua->timeout(500); #useless, need to change the nginx timeout
} else {
    $ua->ssl_opts(
        SSL_cert_file => $valid_ssl_client_cert,
        SSL_key_file  => $valid_ssl_client_key,
        SSL_ca_file   => $ssl_ca_cert,
    );    
}

my $infinite_future;

{
    my $future = NGCP::Panel::Utils::DateTime::infinite_future;
    my $past = NGCP::Panel::Utils::DateTime::infinite_past;
    my $now = NGCP::Panel::Utils::DateTime::current_local;

    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );
    $infinite_future = $dtf->format_datetime($future);
    is($infinite_future,'9999-12-31 23:59:59','check if infinite future is 9999-12-31 23:59:59');
    is($dtf->format_datetime($past),'1000-01-01 00:00:00','check if infinite past is 1000-01-01 00:00:00');
    
    foreach my $offset ((0,'+'. 80*365*24*60*60 .'s','-'. 80*365*24*60*60 .'s')) {

        my ($fake_now,$offset_label);
        if ($offset) {
            _set_time($offset);
            $fake_now = NGCP::Panel::Utils::DateTime::current_local;
            my $delta = $fake_now->epoch - $now->epoch;
            my $delta_offset = substr($offset,0,length($offset)-2) * 1;
            ok(abs($delta) > abs($delta_offset) && abs($delta_offset) > 0,"'Great Scott!'");
            ok($delta > $delta_offset,'check fake time offset of ' . $offset . ': ' . $delta) if $delta_offset > 0;
            ok(-1 * $delta > -1 * $delta_offset,'check fake time offset of ' . $offset . ': ' . $delta) if $delta_offset < 0;
            $offset_label = 'fake time offset: ' . $offset . ': ';
        } else {
            $fake_now = $now;
            $offset_label = '';
        }

        ok($future > $fake_now,$offset_label . 'future is greater than now');
        ok(!($future < $fake_now),$offset_label . 'future is not smaller than now');
        
        ok($past < $fake_now,$offset_label . 'past is smaller than now');
        ok(!($past > $fake_now),$offset_label . 'past is not greater than now');
        
        ok($future->epoch > $fake_now->epoch,$offset_label . 'future is greater than now (epoch)');
        ok(!($future->epoch < $fake_now->epoch),$offset_label . 'future is not smaller than now (epoch)');
        
        ok($past->epoch < $fake_now->epoch,$offset_label . 'past is smaller than now (epoch)');
        ok(!($past->epoch > $fake_now->epoch),$offset_label . 'past is not greater than now (epoch)');    
    }
    #use DateTime::Infinite;
    #$past = DateTime::Infinite::Past->new();
    #$future = DateTime::Infinite::Future->new();
    _set_time();
}

my $t = time;
my $default_reseller_id = 1;

# first, create a contact
$req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    firstname => "cust_contact_first",
    lastname  => "cust_contact_last",
    email     => "cust_contact\@custcontact.invalid",
    reseller_id => $default_reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create customer contact");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch customer contact");
my $custcontact = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    domain => 'test' . ($t-1) . '.example.org',
    reseller_id => $default_reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test domain");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test domain");
my $domain = JSON::from_json($res->decoded_content);


my %customer_map :shared = ();

my $package_map = {};
my $voucher_map = {};
my $subscriber_map = {};
my $profile_map = {};

my $billingprofile = _create_billing_profile("test_default");

my $tb; my $tb_cnt;

if (_get_allow_fake_client_time() && $enable_profile_packages) {
    
    {
        #_start_recording();
        my $network_x = _create_billing_network_x();
        my $network_y = _create_billing_network_y();
        
        my $profile_base_any = _create_billing_profile('BASE_ANY_NETWORK');
        my $profile_base_x = _create_billing_profile('BASE_NETWORK_X');
        my $profile_base_y = _create_billing_profile('BASE_NETWORK_Y');
        
        my $profile_silver_x = _create_billing_profile('SILVER_NETWORK_X');
        my $profile_silver_y = _create_billing_profile('SILVER_NETWORK_Y');
        
        my $profile_gold_x = _create_billing_profile('GOLD_NETWORK_X');
        my $profile_gold_y = _create_billing_profile('GOLD_NETWORK_Y');          
    
        my $base_package = _create_base_profile_package($profile_base_any,$profile_base_x,$profile_base_y,$network_x,$network_y);
        my $silver_package = _create_silver_profile_package($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y);
        my $extension_package = _create_extension_profile_package($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y);
        my $gold_package = _create_gold_profile_package($base_package,$profile_gold_x,$profile_gold_y,$network_x,$network_y);
    
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-05 13:00:00'));
        my $customer_A = _create_customer($base_package,'A');
        my $subscriber_A = _create_subscriber($customer_A,'of customer A');
        #_start_recording();
        my $v_silver_1 = _create_voucher(10,'SILVER_1_'.$t,undef,$silver_package);
        #print _stop_recording();
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-21 13:00:00'));
        
        _perform_topup_voucher($subscriber_A,$v_silver_1);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-10-01 13:00:00'));
        
        _check_interval_history($customer_A,[
            { start => '~2015-06-05 13:00:00', stop => '~2015-06-21 13:00:00', cash => 0, profile => $profile_base_y->{id} },
            { start => '~2015-06-21 13:00:00', stop => '~2015-07-21 13:00:00', cash => 8, profile => $profile_silver_y->{id} },
            { start => '~2015-07-21 13:00:00', stop => '~2015-08-21 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
            { start => '~2015-08-21 13:00:00', stop => '~2015-09-21 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
            { start => '~2015-09-21 13:00:00', stop => '~2015-10-21 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
        ]);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-05 13:00:00'));
        my $customer_B = _create_customer($base_package,'B');
        my $subscriber_B = _create_subscriber($customer_B,'of customer B');
        my $v_silver_2 = _create_voucher(10,'SILVER_2_'.$t,undef,$silver_package);
        my $v_extension_1 = _create_voucher(2,'EXTENSION_1_'.$t,undef,$extension_package);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-27 13:00:00'));
        
        _perform_topup_voucher($subscriber_B,$v_silver_2);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-27 12:00:00'));
        
        _perform_topup_voucher($subscriber_B,$v_extension_1);        
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-10-01 13:00:00'));
        
        _check_interval_history($customer_B,[
            { start => '~2015-06-05 13:00:00', stop => '~2015-06-27 13:00:00', cash => 0, profile => $profile_base_y->{id} },
            { start => '~2015-06-27 13:00:00', stop => '~2015-07-27 13:00:00', cash => 8, profile => $profile_silver_y->{id} },
            { start => '~2015-07-27 13:00:00', stop => '~2015-08-27 13:00:00', cash => 8, profile => $profile_silver_y->{id} },
            { start => '~2015-08-27 13:00:00', stop => '~2015-09-27 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
            { start => '~2015-09-27 13:00:00', stop => '~2015-10-27 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
        ]);
        
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-05 13:00:00'));
        my $customer_C = _create_customer($base_package,'C');
        my $subscriber_C = _create_subscriber($customer_C,'of customer C');
        my $v_gold_1 = _create_voucher(20,'GOLD_1_'.$t,undef,$gold_package);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-02 13:00:00'));
        
        _perform_topup_voucher($subscriber_C,$v_gold_1);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-10-01 13:00:00'));
        
        _check_interval_history($customer_C,[
            { start => '~2015-06-05 13:00:00', stop => '~2015-07-02 13:00:00', cash => 0, profile => $profile_base_y->{id} },
            { start => '~2015-07-02 13:00:00', stop => '~2015-08-02 13:00:00', cash => 15, profile => $profile_gold_y->{id} },
            { start => '~2015-08-02 13:00:00', stop => '~2015-09-02 13:00:00', cash => 15, profile => $profile_gold_y->{id} },
            { start => '~2015-09-02 13:00:00', stop => '~2015-10-02 13:00:00', cash => 15, profile => $profile_gold_y->{id} },
        ]);
        
        _set_time();
        #print _stop_recording();
    }

    my $prof_package_create30d = _create_profile_package('create','day',30);
    my $prof_package_1st30d = _create_profile_package('1st','day',30);
    
    my $prof_package_create1m = _create_profile_package('create','month',1);
    my $prof_package_1st1m = _create_profile_package('1st','month',1);
    
    my $prof_package_create2w = _create_profile_package('create','week',2);
    my $prof_package_1st2w = _create_profile_package('1st','week',2);
    
    my $prof_package_topup = _create_profile_package('topup');  
    
    {
    
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2014-12-30 13:00:00'));
    
        my $customer_topup = _create_customer($prof_package_topup); #create closest to now        
        my $customer_wo = _create_customer();
        my $customer_create1m = _create_customer($prof_package_create1m);
    
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-04-02 02:00:00'));
    
        _check_interval_history($customer_topup,[
            { start => '~2014-12-30 13:00:00', stop => $infinite_future},
        ]);  
        
        _check_interval_history($customer_wo,[
            { start => '2014-12-01 00:00:00', stop => '2014-12-31 23:59:59'},
            { start => '2015-01-01 00:00:00', stop => '2015-01-31 23:59:59'},
            { start => '2015-02-01 00:00:00', stop => '2015-02-28 23:59:59'},
            { start => '2015-03-01 00:00:00', stop => '2015-03-31 23:59:59'},
            { start => '2015-04-01 00:00:00', stop => '2015-04-30 23:59:59'},
        ]); #,NGCP::Panel::Utils::DateTime::from_string('2014-11-29 13:00:00'));
        
        _check_interval_history($customer_create1m,[
            { start => '2014-12-30 00:00:00', stop => '2015-01-29 23:59:59'},
            { start => '2015-01-30 00:00:00', stop => '2015-02-27 23:59:59'},
            { start => '2015-02-28 00:00:00', stop => '2015-03-29 23:59:59'},
            { start => '2015-03-30 00:00:00', stop => '2015-04-29 23:59:59'},
        ]);
        
        _set_time();
    }
    
    {
        my $ts = '2014-01-07 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        my $customer = _create_customer();
    
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
        ]);
        
        $ts = '2014-03-01 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-31 23:59:59'},
        ]);
        
        $customer = _switch_package($customer,$prof_package_create30d);
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
        ]);     
        
        $ts = '2014-04-01 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
            { start => '2014-03-07 00:00:00', stop => '2014-04-05 23:59:59'},
        ]);
        
        $customer = _switch_package($customer,$prof_package_1st30d);
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59'},
        ]);    
        
        $ts = '2014-05-13 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59'},
            { start => '2014-05-01 00:00:00', stop => '2014-05-30 23:59:59'},
        ]);        
        
        $customer = _switch_package($customer,$prof_package_create1m);
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59'},
            { start => '2014-05-01 00:00:00', stop => '2014-06-06 23:59:59'},
        ]);         
        
        $ts = '2014-05-27 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59'},
            { start => '2014-05-01 00:00:00', stop => '2014-06-06 23:59:59'},
        ]);   
        
        $customer = _switch_package($customer,$prof_package_1st1m);
        
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59'},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59'},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59'},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59'},
            { start => '2014-05-01 00:00:00', stop => '2014-05-31 23:59:59'},
        ]);    
        
        my $t1 = $ts;    
        $ts = '2014-08-03 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        $customer = _switch_package($customer,$prof_package_create2w);
        
        _check_interval_history($customer,[
            { start => '2014-06-01 00:00:00', stop => '2014-06-30 23:59:59'},
            { start => '2014-07-01 00:00:00', stop => '2014-07-31 23:59:59'},
            { start => '2014-08-01 00:00:00', stop => '2014-08-06 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));       
        
        $t1 = $ts;
        $ts = '2014-09-03 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        $customer = _switch_package($customer,$prof_package_1st2w);
        
        _check_interval_history($customer,[
            { start => '2014-08-07 00:00:00', stop => '2014-08-20 23:59:59'},
            { start => '2014-08-21 00:00:00', stop => '2014-09-30 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));     
        
        #$t1 = $ts;
        #$ts = '2014-09-03 13:00:00';
        #_set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        $customer = _switch_package($customer);
        
        _check_interval_history($customer,[
            { start => '2014-08-07 00:00:00', stop => '2014-08-20 23:59:59'},
            { start => '2014-08-21 00:00:00', stop => '2014-09-30 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));
        
        $t1 = $ts;
        #my $t1 = '2014-09-03 13:00:00';
        $ts = '2014-10-04 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        $customer = _switch_package($customer,$prof_package_topup);

        _check_interval_history($customer,[
            { start => '2014-10-01 00:00:00', stop => '~2014-10-04 13:00:00'},
            { start => '~2014-10-04 13:00:00', stop => $infinite_future},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));
        
        my $voucher1 = _create_voucher(10,'topup_start_mode_test1'.$t,$customer);
        my $voucher2 = _create_voucher(10,'topup_start_mode_test2'.$t,$customer,$prof_package_create1m);
        my $subscriber = _create_subscriber($customer);

        $t1 = $ts;
        $ts = '2014-10-23 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _check_interval_history($customer,[
            { start => '~2014-10-04 13:00:00', stop => $infinite_future},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));  
        
        _perform_topup_voucher($subscriber,$voucher1);
        
        _check_interval_history($customer,[
           { start => '~2014-10-04 13:00:00', stop => '~2014-10-23 13:00:00'},
            { start => '~2014-10-23 13:00:00', stop => $infinite_future},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));       
        
        $t1 = $ts;
        $ts = '2014-11-29 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _check_interval_history($customer,[
            { start => '~2014-10-23 13:00:00', stop => $infinite_future},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));
        
        _perform_topup_voucher($subscriber,$voucher2);
        
        _check_interval_history($customer,[
            { start => '~2014-10-23 13:00:00', stop => '2014-12-06 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));        
        
        $customer = _switch_package($customer);
        
        _check_interval_history($customer,[
            { start => '~2014-10-23 13:00:00', stop => '2014-11-30 23:59:59', cash => 20},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));        
        
        _set_time();
    }

    {
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-30 13:00:00'));
        
        my $package = _create_profile_package('create','month',1,3);
        my $customer = _create_customer($package);
        my $subscriber = _create_subscriber($customer);
        my $v_notopup = _create_voucher(10,'notopup'.$t);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-02-17 13:00:00'));
        
        _perform_topup_voucher($subscriber,$v_notopup);
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-01 13:00:00'));
        
        _check_interval_history($customer,[
            { start => '2015-01-30 00:00:00', stop => '2015-02-27 23:59:59', cash => 10, topups => 1 }, #topup
            { start => '2015-02-28 00:00:00', stop => '2015-03-29 23:59:59', cash => 10, topups => 0 },
            { start => '2015-03-30 00:00:00', stop => '2015-04-29 23:59:59', cash => 10, topups => 0 },
            { start => '2015-04-30 00:00:00', stop => '2015-05-29 23:59:59', cash => 10, topups => 0 },
            { start => '2015-05-30 00:00:00', stop => '2015-06-29 23:59:59', cash => 0, topups => 0 },
            #{ start => '2015-06-30 00:00:00', stop => '2015-07-29 23:59:59', cash => 0, topups => 0 },
        ]);        
        
        _set_time();
    }    
    
    if (_get_allow_delay_commit()) {
        _set_time(NGCP::Panel::Utils::DateTime::current_local->subtract(months => 3));
        _create_customers_threaded(3);
        _set_time();
        
        my $t1 = time;
        #_fetch_intervals_worker(0,'asc');
        #_fetch_intervals_worker(0,'desc');
        my $delay = 2;
    
        my $t_a = threads->create(\&_fetch_intervals_worker,$delay,'id','asc');
        my $t_b = threads->create(\&_fetch_intervals_worker,$delay,'id','desc');
        my $intervals_a = $t_a->join();
        my $intervals_b = $t_b->join();
        my $t2 = time;
        is_deeply([ sort { $a->{id} cmp $b->{id} } @{ $intervals_b->{_embedded}->{'ngcp:balanceintervals'} } ],$intervals_a->{_embedded}->{'ngcp:balanceintervals'},'compare interval collection results of threaded requests deeply');
        ok($t2 - $t1 > 2*$delay,'expected delay to assume requests were processed after another');
        
    } else {
        diag('allow_delay_commit not set, skipping ...');
    }
} else {
    diag('allow_fake_client_time not set, skipping ...');
}

{ #test balanceintervals root collection and item
    _create_customers_threaded(3) unless _get_allow_fake_client_time() && $enable_profile_packages;
    
    my $total_count = (scalar keys %customer_map);
    my $nexturi = $uri.'/api/balanceintervals/?page=1&rows=' . ((not defined $total_count or $total_count <= 2) ? 2 : $total_count - 1) . '&contact_id='.$custcontact->{id};
    do {
        $req = HTTP::Request->new('GET',$nexturi);
        $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
        $res = $ua->request($req);
        #$res = $ua->get($nexturi);
        is($res->code, 200, "balanceintervals root collection: fetch balance intervals collection page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        is($selfuri, $nexturi, "balanceintervals root collection: check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        ok(defined $total_count ? ($collection->{total_count} == $total_count) : ($collection->{total_count} > 0), "balanceintervals root collection: check 'total_count' of collection");

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, "balanceintervals root collection: check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $collection->{_links}->{prev}->{href}, "balanceintervals root collection: check absence of 'prev' on first page");
        } else {
            ok(exists $collection->{_links}->{prev}->{href}, "balanceintervals root collection: check existence of 'prev'");
        }
        if(($collection->{total_count} / $rows) <= $page) {
            ok(!exists $collection->{_links}->{next}->{href}, "balanceintervals root collection: check absence of 'next' on last page");
        } else {
            ok(exists $collection->{_links}->{next}->{href}, "balanceintervals root collection: check existence of 'next'");
        }

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        ok(ref $collection->{_links}->{'ngcp:balanceintervals'} eq "ARRAY", "balanceintervals root collection: check if 'ngcp:balanceintervals' is array");
        
        my $page_items = {};

        foreach my $interval_link (@{ $collection->{_links}->{'ngcp:balanceintervals'} }) {
            #delete $customers{$c->{href}};
            #ok(exists $journals->{$journal->{href}},"check page journal item link");
            
            $req = HTTP::Request->new('GET',$uri . $interval_link->{href});
            $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
            $res = $ua->request($req);
            is($res->code, 200, "balanceintervals root collection: fetch page balance interval item");
            my $interval = JSON::from_json($res->decoded_content);
            
            $page_items->{$interval->{id}} = $interval;
        }
        foreach my $interval (@{ $collection->{_embedded}->{'ngcp:balanceintervals'} }) {
            ok(exists $page_items->{$interval->{id}},"balanceintervals root collection: check existence of linked item among embedded");
            my $fetched = delete $page_items->{$interval->{id}};
            delete $fetched->{content};
            is_deeply($interval,$fetched,"balanceintervals root collection: compare fetched and embedded item deeply");
        }
        ok((scalar keys $page_items) == 0,"balanceintervals root collection: check if all embedded items are linked");
             
    } while($nexturi);
    
}

done_testing;

sub _check_interval_history {
    
    my ($customer,$expected_interval_history,$limit_dt,$record_label) = @_;
    my $total_count = (scalar @$expected_interval_history);
    #my @got_interval_history = ();
    my $i = 0;
    my $limit = '';
    my $ok = 1;
    my @intervals;
    $limit = '&start=' . DateTime::Format::ISO8601->parse_datetime($limit_dt) if defined $limit_dt;
    my $label = 'interval history of contract with ' . ($customer->{profile_package_id} ? 'package ' . $package_map->{$customer->{profile_package_id}}->{name} : 'no package') . ': ';
    my $nexturi = $uri.'/api/balanceintervals/'.$customer->{id}.'/?page=1&rows=10&order_by_direction=asc&order_by=start'.$limit;
    do {
        $req = HTTP::Request->new('GET',$nexturi);
        $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
        $res = $ua->request($req);        
        #$res = $ua->get($nexturi);
        is($res->code, 200, $label . "fetch balance intervals collection page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        is($selfuri, $nexturi, $label . "check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        $ok = ok($collection->{total_count} == $total_count, $label . "check 'total_count' of collection") && $ok;

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, $label . "check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $collection->{_links}->{prev}->{href}, $label . "check absence of 'prev' on first page");
        } else {
            ok(exists $collection->{_links}->{prev}->{href}, $label . "check existence of 'prev'");
        }
        if(($collection->{total_count} / $rows) <= $page) {
            ok(!exists $collection->{_links}->{next}->{href}, $label . "check absence of 'next' on last page");
        } else {
            ok(exists $collection->{_links}->{next}->{href}, $label . "check existence of 'next'");
        }

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        ok(ref $collection->{_links}->{'ngcp:balanceintervals'} eq "ARRAY", $label . "check if 'ngcp:balanceintervals' is array");
        
        my $page_items = {};

        #foreach my $interval_link (@{ $collection->{_links}->{'ngcp:balanceintervals'} }) {
        #    #delete $customers{$c->{href}};
        #    #ok(exists $journals->{$journal->{href}},"check page journal item link");
        #    
        #    $req = HTTP::Request->new('GET',$uri . $interval_link->{href});
        #    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
        #    $res = $ua->request($req);
        #    is($res->code, 200, $label . "fetch page balance interval item");
        #    my $interval = JSON::from_json($res->decoded_content);
        #    
        #    $page_items->{$interval->{id}} = $interval;
        #}
        foreach my $interval (@{ $collection->{_embedded}->{'ngcp:balanceintervals'} }) {
            #ok(exists $page_items->{$interval->{id}},$label . "check existence of linked item among embedded");
            #my $fetched = delete $page_items->{$interval->{id}};
            #delete $fetched->{content};
            #is_deeply($interval,$fetched,$label . "compare fetched and embedded item deeply");
            $ok = _compare_interval($interval,$expected_interval_history->[$i],$label) && $ok;
            delete $interval->{'_links'};
            push(@intervals,$interval);
            $i++
        }
        #ok((scalar keys $page_items) == 0,$label . "check if all embedded items are linked");
        
        _record_request("view contract balances" . ($record_label ? ' of ' . $record_label : ''),$req,undef,$collection);
             
    } while($nexturi);
    
    ok($i == $total_count,$label . "check if all expected items are listed");
    diag(Dumper(\@intervals)) if !$ok;
    
}

sub _compare_interval {
    my ($got,$expected,$label) = @_;
    
    my $ok = 1;
    if ($expected->{start}) {
        #is(NGCP::Panel::Utils::DateTime::from_string($got->{start}),NGCP::Panel::Utils::DateTime::from_string($expected->{start}),$label . "check interval " . $got->{id} . " start timestmp");
        if (substr($expected->{start},0,1) eq '~') {
            $ok = _is_ts_approx($got->{start},$expected->{start},$label . "check interval " . $got->{id} . " start timestamp") && $ok;
        } else {
            $ok = is($got->{start},$expected->{start},$label . "check interval " . $got->{id} . " start timestmp") && $ok;
        }
    }
    if ($expected->{stop}) {
        #is(NGCP::Panel::Utils::DateTime::from_string($got->{stop}),NGCP::Panel::Utils::DateTime::from_string($expected->{stop}),$label . "check interval " . $got->{id} . " stop timestmp");
        if (substr($expected->{stop},0,1) eq '~') {
            $ok = _is_ts_approx($got->{stop},$expected->{stop},$label . "check interval " . $got->{id} . " stop timestamp") && $ok;
        } else {
            $ok = is($got->{stop},$expected->{stop},$label . "check interval " . $got->{id} . " stop timestmp") && $ok;
        }
    }
    
    if ($expected->{cash}) {
        $ok = is($got->{cash_balance},$expected->{cash},$label . "check interval " . $got->{id} . " cash balance") && $ok;
    }

    if ($expected->{profile}) {
        $ok = is($got->{profile_id},$expected->{profile_id},$label . "check interval " . $got->{id} . " billing profile") && $ok;
    }
    
    if ($expected->{topups}) {
        $ok = is($got->{topup_count},$expected->{topups},$label . "check interval " . $got->{id} . " topup count") && $ok;
    }
    
    if ($expected->{timely_topups}) {
        $ok = is($got->{timely_topup_count},$expected->{timely_topups},$label . "check interval " . $got->{id} . " timely topup count") && $ok;
    }    
    
    return $ok;
    
}

sub _is_ts_approx {
    my ($got,$expected,$label) = @_;
    $got = NGCP::Panel::Utils::DateTime::from_string($got);
    $expected = NGCP::Panel::Utils::DateTime::from_string(substr($expected,1));
    my $epsilon = 10;
    my $lower = $expected->clone->subtract(seconds => $epsilon);
    my $upper = $expected->clone->add(seconds => $epsilon);
    return ok($got >= $lower && $got <= $upper,$label . ' approximately (' . $got . ')');
}

sub _fetch_intervals_worker {
    my ($delay,$sort_column,$dir) = @_;
    diag("starting thread " . threads->tid() . " ...");
    $req = HTTP::Request->new('GET', $uri.'/api/balanceintervals/?order_by='.$sort_column.'&order_by_direction='.$dir.'&contact_id='.$custcontact->{id}.'&rows='.(scalar keys %customer_map));
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $req->header('X-Delay-Commit' => $delay);
    $res = $ua->request($req);
    is($res->code, 200, "thread " . threads->tid() . ": concurrent fetch balanceintervals of " . (scalar keys %customer_map) . " contracts of contact id ".$custcontact->{id} . " in " . $dir . " order");
    my $result = JSON::from_json($res->decoded_content);
    diag("finishing thread " . threads->tid() . " ...");
    return $result;
}

sub _create_customers_threaded {
    my ($number_of_customers) = @_;
    my $t0 = time;
    my @t_cs = ();
    #my $number_of_customers = 3;
    for (1..$number_of_customers) {
        my $t_c = threads->create(\&_create_customer);
        push(@t_cs,$t_c);
    }
    foreach my $t_c (@t_cs) {
        $t_c->join();
    }
    my $t1 = time;
    diag('average time to create a customer: ' . ($t1 - $t0)/$number_of_customers);
}

sub _create_customer {
    
    my ($package,$record_label) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    my $req_data = {
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        ($package ? (billing_profile_definition => 'package',
                     profile_package_id => $package->{id}) :
                     (billing_profile_id => $billingprofile->{id})),
        max_subscribers => undef,
        external_id => undef,
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    my $label = 'test customer ' . ($package ? 'with package ' . $package->{name} : 'w/o profile package');
    is($res->code, 201, "create " . $label);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch " . $label);
    my $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = threads::shared::shared_clone($customer);
    _record_request("create customer" . ($record_label ? ' ' . $record_label : ''),$request,$req_data,$customer);
    return $customer;
    
}

sub _switch_package {
    
    my ($customer,$package) = @_;
    $req = HTTP::Request->new('PATCH', $uri.'/api/customers/'.$customer->{id});
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/profile_package_id', value => ($package ? $package->{id} : undef) } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "patch customer from " . ($customer->{profile_package_id} ? 'package ' . $package_map->{$customer->{profile_package_id}}->{name} : 'no package') . " to " .
       ($package ? $package->{name} : 'no package'));
    $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = threads::shared::shared_clone($customer);
    return $customer;
    
}

sub _set_time {
    my ($o) = @_;
    my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T', 
        );      
    if (defined $o) {
        $o = $o->epoch if ref $o eq 'DateTime';
        Time::Fake->offset($o);
        my $now = NGCP::Panel::Utils::DateTime::current_local;  
        diag("applying fake time offset '$o' - current time: " . $dtf->format_datetime($now));
    } else {
        Time::Fake->reset();
        my $now = NGCP::Panel::Utils::DateTime::current_local;  
        diag("resetting fake time - current time: " . $dtf->format_datetime($now));
    }
}

sub _get_rfc_1123_now {
    return NGCP::Panel::Utils::DateTime::to_rfc1123_string(NGCP::Panel::Utils::DateTime::current_local);
}

sub _create_profile_package {

    my ($start_mode,$interval_unit,$interval_value,$notopup_discard_intervals) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    $req->content(JSON::to_json({
        name => "test '" . $name . "' profile package " . (scalar keys %$package_map) . '_' . $t,
        description  => "test prof package descr " . (scalar keys %$package_map) . '_' . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ],
        balance_interval_start_mode => $start_mode,
        ($interval_unit ? (balance_interval_value => $interval_value,
                            balance_interval_unit => $interval_unit,) : ()),
        notopup_discard_intervals => $notopup_discard_intervals,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage - '" . $name . "'");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage - '" . $name . "'");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    return $package;

}

sub _create_billing_network_x {
    
    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "test billing network X ".$t,
        description  => "billing network Y descr ".$t,
        reseller_id => $default_reseller_id,
        blocks => [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                   {ip=>'fdfe::5a55:caff:fefa:908a'},
                   {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billingnetwork X");
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billingnetwork X");
    my $network = JSON::from_json($res->decoded_content);
    _record_request("create billing network X",$request,$req_data,$network);
    return $network;
}

sub _create_billing_network_y {
    
    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "test billing network Y ".$t,
        description  => "billing network Y descr ".$t,
        reseller_id => $default_reseller_id,
        blocks => [{ip=>'10.0.4.7',mask=>26}, #0..63
                      {ip=>'10.0.4.99',mask=>26}, #64..127
                      {ip=>'10.0.5.9',mask=>24},
                        {ip=>'10.0.6.9',mask=>24},],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billingnetwork Y");
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billingnetwork Y");
    my $network = JSON::from_json($res->decoded_content);
    _record_request("create billing network Y",$request,$req_data,$network);
    return $network;
}

sub _create_base_profile_package {
    
    my ($profile_base_any,$profile_base_x,$profile_base_b,$network_x,$network_b) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    #$req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    #my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    my $req_data = {
        name => "base profile package " . $t,
        description  => "base prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $profile_base_any->{id}, },
                             { profile_id => $profile_base_x->{id}, network_id => $network_x->{id} },
                             { profile_id => $profile_base_b->{id}, network_id => $network_b->{id} }],
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over_timely',
        timely_duration_value => 1,
        timely_duration_unit => 'month',
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test base profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed base profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create BASE profile package",$request,$req_data,$package);
    return $package;        
    
}

sub _create_silver_profile_package {
    
    my ($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    #$req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    #my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    my $req_data = {
        name => "silver profile package " . $t,
        description  => "silver prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => $base_package->{initial_profiles},
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over_timely',
        timely_duration_value => 1,
        timely_duration_unit => 'month',
        
        service_charge => 200,
        topup_profiles => [ #{ profile_id => $profile_silver_any->{id}, },
                             { profile_id => $profile_silver_x->{id}, network_id => $network_x->{id} } ,        
                             { profile_id => $profile_silver_y->{id}, network_id => $network_y->{id} } ],        
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test silver profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed silver profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create SILVER profile package",$request,$req_data,$package);
    return $package;        
    
}

sub _create_extension_profile_package {
    
    my ($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    #$req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    #my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    my $req_data = {
        name => "extension profile package " . $t,
        description  => "extension prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => $base_package->{initial_profiles},
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over_timely',
        timely_duration_value => 1,
        timely_duration_unit => 'month',
        
        service_charge => 200,
        topup_profiles => [ #{ profile_id => $profile_silver_any->{id}, },
                             { profile_id => $profile_silver_x->{id}, network_id => $network_x->{id} } ,        
                             { profile_id => $profile_silver_y->{id}, network_id => $network_y->{id} } ],      
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test extension profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed extension profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create EXTENSION profile package",$request,$req_data,$package);
    return $package;        
    
}

sub _create_gold_profile_package {
    
    my ($base_package,$profile_gold_x,$profile_gold_y,$network_x,$network_y) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    #$req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    #my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    my $req_data = {
        name => "gold profile package " . $t,
        description  => "gold prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => $base_package->{initial_profiles},
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over',
        #timely_duration_value => 1,
        #timely_duration_unit => 'month',
        
        service_charge => 500,
        topup_profiles => [ #{ profile_id => $profile_gold_any->{id}, },
                             { profile_id => $profile_gold_x->{id}, network_id => $network_x->{id} } ,        
                             { profile_id => $profile_gold_y->{id}, network_id => $network_y->{id} } ],       
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test gold profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed gold profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create GOLD profile package",$request,$req_data,$package);
    return $package;        
    
}

sub _create_voucher {
    
    my ($amount,$code,$customer,$package,$valid_until_dt) = @_;
    my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T', 
        );        
    $req = HTTP::Request->new('POST', $uri.'/api/vouchers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    my $req_data = {
        amount => $amount * 100.0,
        code => $code,
        customer_id => ($customer ? $customer->{id} : undef),
        package_id => ($package ? $package->{id} : undef),
        reseller_id => $default_reseller_id,
        valid_until => $dtf->format_datetime($valid_until_dt ? $valid_until_dt : NGCP::Panel::Utils::DateTime::current_local->add(years => 1)),
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    my $label = 'test voucher (' . ($customer ? 'for customer ' . $customer->{id} : 'no customer') . ', ' . ($package ? 'for package ' . $package->{id} : 'no package') . ')';
    is($res->code, 201, "create " . $label);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch " . $label);
    my $voucher = JSON::from_json($res->decoded_content);
    $voucher_map->{$voucher->{id}} = $voucher;
    _record_request("create $amount € voucher (code $code)",$request,$req_data,$voucher);
    return $voucher;
    
}

sub _create_subscriber {
    my ($customer,$record_label) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    my $req_data = {
        domain_id => $domain->{id},
        username => 'cust_subscriber_' . (scalar keys %$subscriber_map) . '_'.$t,
        password => 'cust_subscriber_password',
        customer_id => $customer->{id},
        #status => "active",
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test subscriber");
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriber");
    my $subscriber = JSON::from_json($res->decoded_content);
    $subscriber->{_label} = 'subscriber' . ($record_label ? ' ' . $record_label : '');
    $subscriber_map->{$subscriber->{id}} = $subscriber;
    _record_request("create " . $subscriber->{_label},$request,$req_data,$subscriber);
    return $subscriber;
}

sub _perform_topup_voucher {
    
    my ($subscriber,$voucher) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/topupvouchers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    my $req_data = {
        code => $voucher->{code},
        subscriber_id => $subscriber->{id},
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 204, "perform topup with voucher " . $voucher->{code});
    _record_request("topup by " . $subscriber_map->{$subscriber->{id}}->{_label} . " using " . $voucher->{amount} / 100.0 . " € voucher (code $voucher->{code})",$req,$req_data,undef);
    
}

sub _create_billing_profile {
    my ($name) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => $name." $t",
        handle  => $name."_$t",
        reseller_id => $default_reseller_id,
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billing profile " . $name);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billing profile" . $name);
    my $billingprofile = JSON::from_json($res->decoded_content);
    $profile_map->{$billingprofile->{id}} = $billingprofile;
    _record_request("create billing profile '$name'",$request,$req_data,$billingprofile);
    return $billingprofile;
}

sub _record_request {
    my ($label,$request,$req_data,$res_data) = @_;
    if ($tb) {
        my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T', 
        );
        $tb->add(wrap('',"\t",$tb_cnt . ".\t" . $label . ":"),'');
        my $http_cmd = $request->method . " " . $request->uri;
        $http_cmd =~ s/\?/?\n/;
        $tb->add($http_cmd,' ... at ' . $dtf->format_datetime(NGCP::Panel::Utils::DateTime::current_local));
        $tb->add("Request","Response");
        if ($res_data) {
            $res_data = Storable::dclone($res_data);
            delete $res_data->{"_links"};
            $tb->add($req_data ? to_pretty_json($req_data) : '', to_pretty_json($res_data));
        } else {
            $tb->add($req_data ? to_pretty_json($req_data) : '', '');
        }
        $tb_cnt++;
    };
}

sub _start_recording {
    $tb = Text::Table->new("request", "response");
    $tb_cnt = 1;
}

sub _stop_recording {
    my $output = '';
    if ($tb) {
        $output = $tb->stringify;
    }
    undef $tb;
    undef $tb_cnt;
    return $output;
}

sub to_pretty_json {
    return JSON::to_json(shift, {pretty => 1}); # =~ s/(^\s*{\s*)|(\s*}\s*$)//rg =~ s/\n   /\n/rg;
}

sub _get_allow_delay_commit {
    my $allow_delay_commit = 0;
    my $cfg = $config{api_debug_opts};
    $allow_delay_commit = ((defined $cfg->{allow_delay_commit}) && $cfg->{allow_delay_commit} ? 1 : 0) if defined $cfg;
    return $allow_delay_commit;
}

sub _get_allow_fake_client_time {
    my $allow_fake_client_time = 0;
    my $cfg = $config{api_debug_opts};
    $allow_fake_client_time = ((defined $cfg->{allow_fake_client_time}) && $cfg->{allow_fake_client_time} ? 1 : 0) if defined $cfg;
    return $allow_fake_client_time;
}