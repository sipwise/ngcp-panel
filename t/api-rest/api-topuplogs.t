use strict;
use warnings;

use Scalar::Util qw(looks_like_number);

#use Sipwise::Base; #causes segfault when creating threads..
use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;
use DateTime::Format::Strptime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Storable;

use JSON::PP;
use LWP::Debug;

my $is_local_env = 0;

use Config::General;
my $catalyst_config;
if ($is_local_env) {
    $catalyst_config = Config::General->new("../../ngcp_panel.conf");
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

my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

my $t = time;
my $default_reseller_id = 1;

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


my $customer_map = {};
my $subscriber_map = {};
my $package_map = {};
my $voucher_map = {};
my $profile_map = {};

my $request_count = 0;

#goto SKIP;
{
    my $profile = _create_billing_profile('PROFILE_1');
    
    my $customer = _create_customer(billing_profile_definition => 'id',
        billing_profile_id => $profile->{id},);
    my $subscriber = _create_subscriber($customer);
    my $voucher_1 = _create_voucher(10,'test1'.$t,$customer);
    my $voucher_2 = _create_voucher(10,'test2'.$t,$customer,undef,valid_until => '2010-01-01 00:00:00');

    my $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_cash({ id => 'invalid' },0.5,undef,$request_token,422);
    _check_topup_log('failing topup cash validation (subscriber_id): ',[
        { outcome => 'failed', request_token => $request_token, message => 'Validation failed. field=\'subscriber_id\'' }
    ],'request_token='.$request_token);
    
    $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_cash($subscriber,'invalid_amount',undef,$request_token,422);
    _check_topup_log('failing topup cash validation (amount): ',[
        { outcome => 'failed', request_token => $request_token, message => 'Value cannot be converted to money' }
    ],'request_token='.$request_token);
    
    $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_cash($subscriber,50,{ id => 'invalid' },$request_token,422);
    _check_topup_log('failing topup cash validation (package_id): ',[
        { outcome => 'failed', request_token => $request_token, message => 'Validation failed. field=\'package_id\'' }
    ],'request_token='.$request_token);    
    
    $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_voucher($subscriber,{ code => 'invalid' },$request_token,422);
    _check_topup_log('failing topup voucher validation (voucher code): ',[
        { outcome => 'failed', request_token => $request_token, message => 'Invalid voucher code \'invalid\'' }
    ],'request_token='.$request_token);    
    
    $request_token = $t."_".$request_count; $request_count++;
    $request_token .= 'a' x (256 - length($request_token));
    _perform_topup_voucher($subscriber,$voucher_1,$request_token,422);
    _check_topup_log('failing topup voucher validation (request_token): ',[
        { outcome => 'failed', request_token => substr($request_token,0,255), message => 'Validation failed. field=\'request_token\'' }, #'Field should not exceed 255 characters' }
    ],'request_token='.substr($request_token,0,255));
    
    $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_voucher($subscriber,$voucher_1,$request_token);
    $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_voucher($subscriber,$voucher_1,$request_token,422);
    _check_topup_log('failing topup voucher validation (voucher used): ',[
        { outcome => 'failed', request_token => $request_token, message => 'already used' }
    ],'request_token='.$request_token);
    
    $request_token = $t."_".$request_count; $request_count++;
    _perform_topup_voucher($subscriber,$voucher_2,$request_token,422);
    _check_topup_log('failing topup voucher validation (voucher expired): ',[
        { outcome => 'failed', request_token => $request_token, message => 'expired' }
    ],'request_token='.$request_token);      
    
}

SKIP:
{
    my $profile_initial_1 = _create_billing_profile('INITIAL1');
    my $profile_topup_1 = _create_billing_profile('TOPUP1');
    #my $profile_underrun = _create_billing_profile('UNDERRUN');

    my $package_1 = _create_profile_package('1st','month',1, initial_balance => 100,
            #carry_over_mode => 'discard', underrun_lock_threshold => 50, underrun_lock_level => 4, underrun_profile_threshold => 50,
            initial_profiles => [ { profile_id => $profile_initial_1->{id}, }, ],
            topup_profiles => [ { profile_id => $profile_topup_1->{id}, }, ],
            #underrun_profiles => [ { profile_id => $profile_underrun->{id}, }, ],
            );
    
    
    
    my $customer = _create_customer(billing_profile_definition => 'package',
        profile_package_id => $package_1->{id},);
    my $subscriber = _create_subscriber($customer);
    my $voucher_1 = _create_voucher(10,'test3'.$t,$customer);

    my $request_token_1 = $t."_".$request_count; $request_count++;
    _perform_topup_cash($subscriber,0.5,undef,$request_token_1);
    my $request_token_2 = $t."_".$request_count; $request_count++;
    _perform_topup_voucher($subscriber,$voucher_1,$request_token_2);
    
    _check_topup_log('successful topups - subscriber_id, outcome filter: ',[
        { outcome => 'ok', request_token => $request_token_1 },
        { outcome => 'ok', request_token => $request_token_2 },
    ],'subscriber_id='.$subscriber->{id}.'&outcome=ok');
    
    _check_topup_log('successful topups - contract_id filter: ',[
        { outcome => 'ok', request_token => $request_token_1 },
        { outcome => 'ok', request_token => $request_token_2 },
    ],'contract_id='.$customer->{id});

    my $profile_initial_2 = _create_billing_profile('INITIAL2');
    my $profile_topup_2 = _create_billing_profile('TOPUP2');
    #my $profile_underrun = _create_billing_profile('UNDERRUN');

    my $package_2 = _create_profile_package('1st','month',1, initial_balance => 100,
            #carry_over_mode => 'discard', underrun_lock_threshold => 50, underrun_lock_level => 4, underrun_profile_threshold => 50,
            initial_profiles => [ { profile_id => $profile_initial_2->{id}, }, ],
            topup_profiles => [ { profile_id => $profile_topup_2->{id}, }, ],
            #underrun_profiles => [ { profile_id => $profile_underrun->{id}, }, ],
            );
    
    my $voucher_2 = _create_voucher(30,'test4'.$t,$customer,$package_2);
    my $request_token_3 = $t."_".$request_count; $request_count++;
    _perform_topup_voucher($subscriber,$voucher_2,$request_token_3);

    _check_topup_log('successful topups - voucher_id filter: ',[
        { outcome => 'ok', request_token => $request_token_3 },
    ],'voucher_id='.$voucher_2->{id});
    
    _check_topup_log('successful topups - amount_above filter: ',[
        { outcome => 'ok', request_token => $request_token_2 },        
        { outcome => 'ok', request_token => $request_token_3 },
    ],'amount_above=1&subscriber_id='.$subscriber->{id});

    _check_topup_log('successful topups - amount_below filter: ',[
        { outcome => 'ok', request_token => $request_token_1 },        
        { outcome => 'ok', request_token => $request_token_2 },
    ],'amount_below=10&subscriber_id='.$subscriber->{id});
    
    _check_topup_log('successful topups - timestamp_from filter: ',[
        { outcome => 'ok', request_token => $request_token_1 },        
        { outcome => 'ok', request_token => $request_token_2 },
        { outcome => 'ok', request_token => $request_token_3 },        
    ],'timestamp_from=2000-01-01T00:00:00&subscriber_id='.$subscriber->{id});

    _check_topup_log('successful topups - balance before/after: ',[
        { outcome => 'ok', cash_balance_before => 1, cash_balance_after => 1.5, request_token => $request_token_1 },        
        { outcome => 'ok', cash_balance_before => 1.5, cash_balance_after => 11.5, request_token => $request_token_2 },
        { outcome => 'ok', cash_balance_before => 11.5, cash_balance_after => 41.5, request_token => $request_token_3 },  
    ],'contract_id='.$customer->{id});    

    _check_topup_log('successful topups - package before/after: ',[
        { outcome => 'ok', package_before_id=> $package_1->{id}, package_after_id=> $package_1->{id}, request_token => $request_token_1 },        
        { outcome => 'ok', package_before_id=> $package_1->{id}, package_after_id=> $package_1->{id}, request_token => $request_token_2 },
        { outcome => 'ok', package_before_id=> $package_1->{id}, package_after_id=> $package_2->{id}, request_token => $request_token_3 },     
    ],'contract_id='.$customer->{id});        
    
    _check_topup_log('successful topups - profile before/after: ',[
        { outcome => 'ok', profile_before_id => $profile_initial_1->{id}, profile_after_id => $profile_topup_1->{id}, request_token => $request_token_1 },        
        { outcome => 'ok', profile_before_id => $profile_topup_1->{id}, profile_after_id => $profile_topup_1->{id}, request_token => $request_token_2 },
        { outcome => 'ok', profile_before_id => $profile_topup_1->{id}, profile_after_id => $profile_topup_2->{id},request_token => $request_token_3 },  
    ],'contract_id='.$customer->{id});    
    
}
    
done_testing;

sub _check_topup_log {
    
    my ($label,$expected_topup_log,$filter_query) = @_;
    my $total_count = (scalar @$expected_topup_log);
    my $i = 0;
    my $nexturi = $uri.'/api/topuplogs/?page=1&rows=10&order_by_direction=asc&order_by=timestamp'.(defined $filter_query ? '&'.$filter_query : '');
    do {
        $req = HTTP::Request->new('GET',$nexturi);
        $res = $ua->request($req);        
        #$res = $ua->get($nexturi);
        is($res->code, 200, $label."fetch topup log collection page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        #is($selfuri, $nexturi, $label."check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        ok($collection->{total_count} == $total_count, $label."check 'total_count' of collection");

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, $label."check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $collection->{_links}->{prev}->{href}, $label."check absence of 'prev' on first page");
        } else {
            ok(exists $collection->{_links}->{prev}->{href}, $label."check existence of 'prev'");
        }
        if(($collection->{total_count} / $rows) <= $page) {
            ok(!exists $collection->{_links}->{next}->{href}, $label."check absence of 'next' on last page");
        } else {
            ok(exists $collection->{_links}->{next}->{href}, $label."check existence of 'next'");
        }

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        ok(ref $collection->{_embedded}->{'ngcp:topuplogs'} eq "ARRAY", $label."check if 'ngcp:topuplogs' is array");
        
        #my $page_items = {};

        foreach my $log_record (@{ $collection->{_embedded}->{'ngcp:topuplogs'} }) {
            #$req = HTTP::Request->new('GET',$uri.$log_record->{_links}->{self}->{href});
            #$res = $ua->request($req);        
            #is($res->code, 200, $label."fetch topup log entry");
            #my $got = JSON::from_json($res->decoded_content);
            #is_deeply($got,$log_record,$label.'check topup log entry deeply');
            _compare_log_record($label,$log_record,$expected_topup_log->[$i]);
            $i++
        }
             
    } while($nexturi);
    
    ok($i == $total_count,$label."check if all expected items are listed");
    
}

sub _compare_log_record {
    my ($label,$got,$expected) = @_;
    
    foreach my $field (keys %$expected) {
        if ('message' eq $field) {
            ok($got->{$field} =~ /$expected->{$field}/,$label."check log '" . $field . "': " . $got->{$field} . " =~ /" . $expected->{$field} . '/');
        } else {
            is($got->{$field},$expected->{$field},$label."check log '" . $field . "': " . $got->{$field} . " = " . $expected->{$field});
        }
    }

}

sub _create_customer {
    
    my (@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    my $req_data = {
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        max_subscribers => undef,
        external_id => undef,
        @further_opts
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "create test customer");
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test customer");
    my $customer = JSON::from_json($res->decoded_content);
    $customer_map->{$customer->{id}} = $customer;
    return $customer;
    
}

sub _create_profile_package {

    my ($start_mode,$interval_unit,$interval_value,@further_opts) = @_; #$notopup_discard_intervals
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    $req->content(JSON::to_json({
        name => "test '" . $name . "' profile package " . (scalar keys %$package_map) . '_' . $t,
        #description  => "test prof package descr " . (scalar keys %$package_map) . '_' . $t,
        description  => $start_mode . "/" . $interval_value . " " . $interval_unit . "s",
        reseller_id => $default_reseller_id,
        #initial_profiles => [{ profile_id => $billingprofile->{id}, }, ],
        balance_interval_start_mode => $start_mode,
        ($interval_unit ? (balance_interval_value => $interval_value,
                            balance_interval_unit => $interval_unit,) : ()),
        #notopup_discard_intervals => $notopup_discard_intervals,
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage - '" . $name . "'");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage - '" . $name . "'");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    return $package;

}

sub _create_voucher {
    
    my ($amount,$code,$customer,$package,@further_opts) = @_;
    my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T', 
        );        
    $req = HTTP::Request->new('POST', $uri.'/api/vouchers/');
    $req->header('Content-Type' => 'application/json');
    my $req_data = {
        amount => $amount * 100.0,
        code => $code,
        customer_id => ($customer ? $customer->{id} : undef),
        package_id => ($package ? $package->{id} : undef),
        reseller_id => $default_reseller_id,
        valid_until => '2037-01-01 00:00:00',
        @further_opts,
        #valid_until => $dtf->format_datetime($valid_until_dt ? $valid_until_dt : NGCP::Panel::Utils::DateTime::current_local->add(years => 1)),
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    my $label = 'test voucher (' . ($customer ? 'for customer ' . $customer->{id} : 'no customer') . ', ' . ($package ? 'for package ' . $package->{id} : 'no package') . ')';
    is($res->code, 201, "create " . $label);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch " . $label);
    my $voucher = JSON::from_json($res->decoded_content);
    $voucher_map->{$voucher->{id}} = $voucher;
    return $voucher;
    
}

sub _create_subscriber {
    my ($customer) = @_;
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
    $subscriber_map->{$subscriber->{id}} = $subscriber;
    return $subscriber;

}

sub _perform_topup_voucher {
    
    my ($subscriber,$voucher,$request_token,$error_code) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/topupvouchers/');
    $req->header('Content-Type' => 'application/json');
    my $req_data = {
        code => $voucher->{code},
        subscriber_id => $subscriber->{id},
        (defined $request_token ? (request_token => $request_token) : ()),
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    $error_code //= 204;
    is($res->code, $error_code, ($error_code == 204 ? 'perform' : 'attempt')." perform topup with voucher " . $voucher->{code});
    
}

sub _perform_topup_cash {
    
    my ($subscriber,$amount,$package,$request_token,$error_code) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/topupcash/');
    $req->header('Content-Type' => 'application/json');
    my $req_data = {
        amount => ( looks_like_number($amount) ? $amount * 100.0 : $amount),
        package_id => ($package ? $package->{id} : undef),
        subscriber_id => $subscriber->{id},
        (defined $request_token ? (request_token => $request_token) : ()),
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    $error_code //= 204;
    is($res->code, $error_code, ($error_code == 204 ? 'perform' : 'attempt')." topup with amount " . ( looks_like_number($amount) ? $amount * 100.0 . ' cents' : $amount) . ", " . ($package ? 'package id ' . $package->{id} : 'no package'));
    
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
    is($res->code, 200, "fetch POSTed billing profile " . $name);
    my $billingprofile = JSON::from_json($res->decoded_content);
    $profile_map->{$billingprofile->{id}} = $billingprofile;
    return $billingprofile;
}
