
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


use JSON::PP;
use LWP::Debug;

BEGIN {
    unshift(@INC,'../lib');
}
use NGCP::Panel::Utils::DateTime qw();

my $is_local_env = 1;


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

{
    my $future = NGCP::Panel::Utils::DateTime::infinite_future;
    my $past = NGCP::Panel::Utils::DateTime::infinite_past;
    my $now = NGCP::Panel::Utils::DateTime::current_local;

    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );
    is($dtf->format_datetime($future),'9999-12-31 23:59:59','check if infinite future is 9999-12-31 23:59:59');
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

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => $default_reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test billing profile");
my $billingprofile_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingprofile_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed billing profile");
my $billingprofile = JSON::from_json($res->decoded_content);

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

my %customer_map :shared = ();

my $profile_map = {};

if (_get_allow_fake_client_time()) {

    my $prof_package_create30d = _create_profile_package('create','day',30);
    my $prof_package_1st30d = _create_profile_package('1st','day',30);
    
    my $prof_package_create1m = _create_profile_package('create','month',1);
    my $prof_package_1st1m = _create_profile_package('1st','month',1);
    
    my $prof_package_create2w = _create_profile_package('create','week',2);
    my $prof_package_1st2w = _create_profile_package('1st','week',2);
    
    my $prof_package_topup = _create_profile_package('topup');
    
    {
        
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2014-12-30 13:00:00'));
        
        my $customer_wo = _create_customer();
        my $customer_create1m = _create_customer($prof_package_create1m);
    
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-04-02 02:00:00'));
        
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
        
        _switch_package($customer,$prof_package_create30d);
        
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
        
        _switch_package($customer,$prof_package_1st30d);
        
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
        
        _switch_package($customer,$prof_package_create1m);
        
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
        
        _switch_package($customer,$prof_package_1st1m);
    
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
        
        _switch_package($customer,$prof_package_create2w);
        
        _check_interval_history($customer,[
            { start => '2014-06-01 00:00:00', stop => '2014-06-30 23:59:59'},
            { start => '2014-07-01 00:00:00', stop => '2014-07-31 23:59:59'},
            { start => '2014-08-01 00:00:00', stop => '2014-08-06 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));       
        
        $t1 = $ts;
        $ts = '2014-09-03 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _switch_package($customer,$prof_package_1st2w);
        
        _check_interval_history($customer,[
            { start => '2014-08-07 00:00:00', stop => '2014-08-20 23:59:59'},
            { start => '2014-08-21 00:00:00', stop => '2014-09-30 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));     
        
        #$t1 = $ts;
        #$ts = '2014-09-03 13:00:00';
        #_set_time(NGCP::Panel::Utils::DateTime::from_string($ts));
        
        _switch_package($customer);
        
        _check_interval_history($customer,[
            { start => '2014-08-07 00:00:00', stop => '2014-08-20 23:59:59'},
            { start => '2014-08-21 00:00:00', stop => '2014-09-30 23:59:59'},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));       
        
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
    _create_customers_threaded(3) unless _get_allow_fake_client_time();
    
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
    
    my ($customer,$expected_interval_history,$limit_dt) = @_;
    my $total_count = (scalar @$expected_interval_history);
    #my @got_interval_history = ();
    my $i = 0;
    my $limit = '';
    $limit = '&start=' . DateTime::Format::ISO8601->parse_datetime($limit_dt) if defined $limit_dt;
    my $label = 'interval history of contract with ' . ($customer->{profile_package_id} ? 'package ' . $profile_map->{$customer->{profile_package_id}}->{name} : 'no package') . ': ';
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

        ok($collection->{total_count} == $total_count, $label . "check 'total_count' of collection");

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
            _compare_interval($interval,$expected_interval_history->[$i],$label);
            $i++
        }
        #ok((scalar keys $page_items) == 0,$label . "check if all embedded items are linked");
             
    } while($nexturi);
    
    ok($i == $total_count,$label . "check if all expected items are listed");
    
}

sub _compare_interval {
    my ($got,$expected,$label) = @_;
    
    if ($expected->{start}) {
        is(NGCP::Panel::Utils::DateTime::from_string($got->{start}),NGCP::Panel::Utils::DateTime::from_string($expected->{start}),$label . "check interval " . $got->{id} . " start timestmp");
    }
    if ($expected->{stop}) {
        is(NGCP::Panel::Utils::DateTime::from_string($got->{stop}),NGCP::Panel::Utils::DateTime::from_string($expected->{stop}),$label . "check interval " . $got->{id} . " stop timestmp");
    }
    
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
    
    my ($package) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        ($package ? (billing_profile_definition => 'package',
                     profile_package_id => $package->{id}) :
                     (billing_profile_id => $billingprofile->{id})),
        max_subscribers => undef,
        external_id => undef,
    }));
    $res = $ua->request($req);
    my $label = 'test customer ' . ($package ? 'with package ' . $package->{name} : 'w/o profile package');
    is($res->code, 201, "create " . $label);
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch " . $label);
    my $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = threads::shared::shared_clone($customer);
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
    is($res->code, 200, "patch customer from " . ($customer->{profile_package_id} ? 'package ' . $profile_map->{$customer->{profile_package_id}}->{name} : 'no package') . " to " .
       ($package ? $package->{name} : 'no package'));
    return JSON::from_json($res->decoded_content);
    
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

    my ($start_mode,$interval_unit,$interval_value) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    $req->content(JSON::to_json({
        name => "test '" . $name . "' profile package " . $t,
        description  => "test profile package description " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ],
        balance_interval_start_mode => $start_mode,
        ($interval_unit ? (balance_interval_value => $interval_value,
                            balance_interval_unit => $interval_unit,) : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage - '" . $name . "'");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_rfc_1123_now());
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage - '" . $name . "'");
    my $package = JSON::from_json($res->decoded_content);
    $profile_map->{$package->{id}} = $package;
    return $package;

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