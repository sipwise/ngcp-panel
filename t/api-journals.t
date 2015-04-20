use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use Storable qw();

use JSON::PP;
use LWP::Debug;

BEGIN {
    unshift(@INC,'../lib');
}
use NGCP::Panel::Utils::Journal qw();

my $is_local_env = 0;
my $mysql_sqlstrict = not $is_local_env;
my $enable_journal_tests = 1;

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

my $t = time;
my $default_reseller_id = 1;

my $billingprofile = test_billingprofile($t,$default_reseller_id);
my $systemcontact = test_systemcontact($t);
my $contract = test_contract($billingprofile,$systemcontact);
(my $reseller,$billingprofile) = test_reseller($t,$contract);
my $domain = test_domain($t,$reseller);
my $customercontact = test_customercontact($t,$reseller);
my $customer = test_customer($customercontact,$billingprofile);
my $customerpreferences = test_customerpreferences($customer);

my $subscriberprofileset = test_subscriberprofileset($t,$reseller);
my $subscriberprofile = test_subscriberprofile($t,$subscriberprofileset);
my $profilepreferences = test_profilepreferences($subscriberprofile);

my $subscriber = test_subscriber($t,$customer,$domain);

my $voicemailsettings = test_voicemailsettings($t,$subscriber);

my $trustedsource = test_trustedsource($subscriber);

my $speeddials = test_speeddials($t,$subscriber);

my $reminder = test_reminder($subscriber);

my $faxserversettings = test_faxserversettings($t,$subscriber);


my $ccmapentries = test_ccmapentries($subscriber);

my $cfdestinationset = test_cfdestinationset($t,$subscriber);
my $cftimeset = test_cftimeset($t,$subscriber);
test_callforwards($subscriber,$cfdestinationset,$cftimeset);
my $cfmappings = test_cfmapping($subscriber,$cfdestinationset,$cftimeset);


my $systemsoundset = test_soundset($t,$reseller);
my $customersoundset = test_soundset($t,$reseller,$customer);
my $subscriberpreferences = test_subscriberpreferences($subscriber,$customersoundset,$systemsoundset);




done_testing;

sub test_voicemailsettings {
    my ($t,$subscriber) = @_;

    my $voicemailsettings_uri = $uri.'/api/voicemailsettings/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $voicemailsettings_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    $req->content(JSON::to_json({
        attach => JSON::PP::true,
        delete => JSON::PP::true,
        email =>  'voicemail_email_'.$t.'@example.com',
        pin => '1234',
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test voicemailsettings");
    $req = HTTP::Request->new('GET', $voicemailsettings_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test voicemailsettings");
    my $voicemailsettings = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('voicemailsettings',$voicemailsettings,$subscriber->{id});
    _test_journal_options_head('voicemailsettings',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('voicemailsettings',$subscriber->{id},$voicemailsettings,'update',$journals);
    _test_journal_options_head('voicemailsettings',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $voicemailsettings_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/pin', value => '4567' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test voicemailsettings");
    $req = HTTP::Request->new('GET', $voicemailsettings_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test voicemailsettings");
    $voicemailsettings = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('voicemailsettings',$voicemailsettings,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('voicemailsettings',$subscriber->{id},$voicemailsettings,'update',$journals,$journal);
    
    _test_journal_collection('voicemailsettings',$subscriber->{id},$journals);
    
    return $voicemailsettings;
    
}

sub test_trustedsource {
    my ($subscriber) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/trustedsources/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        #from_pattern => 
        protocol => 'TCP', #UDP, TCP, TLS, ANY
        src_ip => '192.168.0.1',
        subscriber_id => $subscriber->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test trustedsource");
    my $trustedsource_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $trustedsource_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test trustedsource");
    my $trustedsource = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('trustedsources',$trustedsource,$trustedsource->{id});
    _test_journal_options_head('trustedsources',$trustedsource->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('trustedsources',$trustedsource->{id},$trustedsource,'create',$journals);
    _test_journal_options_head('trustedsources',$trustedsource->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $trustedsource_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        #from_pattern => 
        protocol => 'TCP', #UDP, TCP, TLS, ANY
        src_ip => '192.168.0.2',
        subscriber_id => $subscriber->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test trustedsource");
    $req = HTTP::Request->new('GET', $trustedsource_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test trustedsource");
    $trustedsource = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('trustedsources',$trustedsource,$trustedsource->{id});    
    $journal = _test_journal_top_journalitem('trustedsources',$trustedsource->{id},$trustedsource,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $trustedsource_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/src_ip', value => '192.168.0.3' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test trustedsource");
    $req = HTTP::Request->new('GET', $trustedsource_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test trustedsource");
    $trustedsource = JSON::from_json($res->decoded_content);

    _test_item_journal_link('trustedsources',$trustedsource,$trustedsource->{id});    
    $journal = _test_journal_top_journalitem('trustedsources',$trustedsource->{id},$trustedsource,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $trustedsource_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test trustedsource");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('trustedsources',$trustedsource->{id},$trustedsource,'delete',$journals,$journal);
    
    _test_journal_collection('trustedsources',$trustedsource->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/trustedsources/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        #from_pattern => 
        protocol => 'TCP', #UDP, TCP, TLS, ANY
        src_ip => '192.168.0.1',
        subscriber_id => $subscriber->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test trustedsource");
    $trustedsource_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $trustedsource_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test trustedsource");
    $trustedsource = JSON::from_json($res->decoded_content);
    
    return $trustedsource;
    
}



sub test_speeddials {
    my ($t,$subscriber) = @_;

    my $speeddials_uri = $uri.'/api/speeddials/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $speeddials_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    $req->content(JSON::to_json({
        speeddials => [ {slot => '*1',
                         destination => 'speed_dial_dest_'.$t.'@example.com' },
                       {slot => '*2',
                         destination => 'speed_dial_dest_'.$t.'@example.com' },
                       {slot => '*3',
                         destination => 'speed_dial_dest_'.$t.'@example.com' },],
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test speeddials");
    $req = HTTP::Request->new('GET', $speeddials_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test speeddials");
    my $speeddials = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('speeddials',$speeddials,$subscriber->{id});
    _test_journal_options_head('speeddials',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('speeddials',$subscriber->{id},$speeddials,'update',$journals);
    _test_journal_options_head('speeddials',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $speeddials_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/speeddials', value => [ {slot => '*4',
                         destination => 'speed_dia_dest_'.$t.'@example.com' },
                       {slot => '*5',
                         destination => 'speed_dia_dest_'.$t.'@example.com' },
                       {slot => '*6',
                         destination => 'speed_dia_dest_'.$t.'@example.com' },] } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test speeddials");
    $req = HTTP::Request->new('GET', $speeddials_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test speeddials");
    $speeddials = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('speeddials',$speeddials,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('speeddials',$subscriber->{id},$speeddials,'update',$journals,$journal);
    
    _test_journal_collection('speeddials',$subscriber->{id},$journals);
    
    return $speeddials;
    
}


sub test_reminder {
    my ($subscriber) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/reminders/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        recur => 'never', #, 'weekdays', 'always',
        subscriber_id => $subscriber->{id},
        'time' => '10:00:00',
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test reminder");
    my $reminder_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $reminder_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test reminder");
    my $reminder = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('reminders',$reminder,$reminder->{id});
    _test_journal_options_head('reminders',$reminder->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('reminders',$reminder->{id},$reminder,'create',$journals);
    _test_journal_options_head('reminders',$reminder->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $reminder_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        recur => 'never', #, 'weekdays', 'always',
        subscriber_id => $subscriber->{id},
        'time' => '11:00:00',
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test reminder");
    $req = HTTP::Request->new('GET', $reminder_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test reminder");
    $reminder = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('reminders',$reminder,$reminder->{id});    
    $journal = _test_journal_top_journalitem('reminders',$reminder->{id},$reminder,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $reminder_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/recur', value => 'weekdays' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test reminder");
    $req = HTTP::Request->new('GET', $reminder_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test reminder");
    $reminder = JSON::from_json($res->decoded_content);

    _test_item_journal_link('reminders',$reminder,$reminder->{id});    
    $journal = _test_journal_top_journalitem('reminders',$reminder->{id},$reminder,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $reminder_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test reminder");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('reminders',$reminder->{id},$reminder,'delete',$journals,$journal);
    
    _test_journal_collection('reminders',$reminder->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/reminders/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        recur => 'never', #, 'weekdays', 'always',
        subscriber_id => $subscriber->{id},
        'time' => '10:00:00',
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test reminder");
    $reminder_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $reminder_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test reminder");
    $reminder = JSON::from_json($res->decoded_content);
    
    return $reminder;
    
}


sub test_faxserversettings {
    my ($t,$subscriber) = @_;

    my $faxserversettings_uri = $uri.'/api/faxserversettings/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $faxserversettings_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    $req->content(JSON::to_json({
        active => JSON::PP::true,
        destinations => [ {destination => 'test_fax_destination_'.$t.'@example.com', #??
                           filetype => 'TIFF',
                           cc => JSON::PP::true,
                           incoming => JSON::PP::true,
                           outgoing => JSON::PP::false,
                           status => JSON::PP::true,} ],
        name => 'fax_server_settings_'.$t,
        password => 'fax_server_settings_password_'.$t,
        send_copy => JSON::PP::false,
        send_status => JSON::PP::false,
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test faxserversettings");
    $req = HTTP::Request->new('GET', $faxserversettings_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test faxserversettings");
    my $faxserversettings = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('faxserversettings',$faxserversettings,$subscriber->{id});
    _test_journal_options_head('faxserversettings',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('faxserversettings',$subscriber->{id},$faxserversettings,'update',$journals);
    _test_journal_options_head('faxserversettings',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $faxserversettings_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/active', value => JSON::PP::false } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test faxserversettings");
    $req = HTTP::Request->new('GET', $faxserversettings_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test faxserversettings");
    $faxserversettings = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('faxserversettings',$faxserversettings,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('faxserversettings',$subscriber->{id},$faxserversettings,'update',$journals,$journal);
    
    _test_journal_collection('faxserversettings',$subscriber->{id},$journals);
    
    return $faxserversettings;
    
}


sub test_ccmapentries {
    my ($subscriber) = @_;

    my $ccmapentries_uri = $uri.'/api/ccmapentries/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $ccmapentries_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    $req->content(JSON::to_json({
        mappings => [ { auth_key => 'abc' },
                      { auth_key => 'def' },
                      { auth_key => 'ghi' } ]
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test ccmapentries");
    $req = HTTP::Request->new('GET', $ccmapentries_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test ccmapentries");
    my $ccmapentries = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('ccmapentries',$ccmapentries,$subscriber->{id});
    _test_journal_options_head('ccmapentries',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('ccmapentries',$subscriber->{id},$ccmapentries,'update',$journals);
    _test_journal_options_head('ccmapentries',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $ccmapentries_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/mappings', value => [ { auth_key => 'jkl' },
                      { auth_key => 'mno' },
                      { auth_key => 'pqr' } ] } ] 
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test ccmapentries");
    $req = HTTP::Request->new('GET', $ccmapentries_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test ccmapentries");
    $ccmapentries = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('ccmapentries',$ccmapentries,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('ccmapentries',$subscriber->{id},$ccmapentries,'update',$journals,$journal);

    $req = HTTP::Request->new('DELETE', $ccmapentries_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete PATCHed test ccmapentries");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('ccmapentries',$subscriber->{id},$ccmapentries,'delete',$journals,$journal);

    _test_journal_collection('ccmapentries',$subscriber->{id},$journals);
    
    return undef;
    
}




sub test_callforwards {
    my ($subscriber,$cfdestinationset,$cftimeset) = @_;

    my $callforward_uri = $uri.'/api/callforwards/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $callforward_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    $req->content(JSON::to_json({
        cfb => { destinations => $cfdestinationset->{destinations},
                 times => $cftimeset->{times}},
        cfna => { destinations => $cfdestinationset->{destinations},
                 times => $cftimeset->{times}},
        cft => { destinations => $cfdestinationset->{destinations},
                 times => $cftimeset->{times}},
        cfu => { destinations => $cfdestinationset->{destinations},
                 times => $cftimeset->{times}},        
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test callforwards");
    $req = HTTP::Request->new('GET', $callforward_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test callforwards");
    my $callforwards = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('callforwards',$callforwards,$subscriber->{id});
    _test_journal_options_head('callforwards',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('callforwards',$subscriber->{id},$callforwards,'update',$journals);
    _test_journal_options_head('callforwards',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $callforward_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/cfb', value => {destinations => $cfdestinationset->{destinations},
                 times => $cftimeset->{times}} } ] 
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test callforwards");
    $req = HTTP::Request->new('GET', $callforward_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test callforwards");
    $callforwards = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('callforwards',$callforwards,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('callforwards',$subscriber->{id},$callforwards,'update',$journals,$journal);

    $req = HTTP::Request->new('DELETE', $callforward_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete PATCHed test callforwards");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('callforwards',$subscriber->{id},$callforwards,'delete',$journals,$journal);

    _test_journal_collection('callforwards',$subscriber->{id},$journals);
    
    return undef;
    
}


sub test_cfmapping {
    my ($subscriber,$cfdestinationset,$cftimeset) = @_;

    my $cfmapping_uri = $uri.'/api/cfmappings/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $cfmapping_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    $req->content(JSON::to_json({
        cfb => [{ destinationset => $cfdestinationset->{name},
                 timeset => $cftimeset->{name}}],
        cfna => [{ destinationset => $cfdestinationset->{name},
                 timeset => $cftimeset->{name}}],
        cft => [{ destinationset => $cfdestinationset->{name},
                 timeset => $cftimeset->{name}}],
        cfu => [{ destinationset => $cfdestinationset->{name},
                 timeset => $cftimeset->{name}}],        
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test cfmappings");
    $req = HTTP::Request->new('GET', $cfmapping_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test cfmappings");
    my $cfmappings = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('cfmappings',$cfmappings,$subscriber->{id});
    _test_journal_options_head('cfmappings',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('cfmappings',$subscriber->{id},$cfmappings,'update',$journals);
    _test_journal_options_head('cfmappings',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $cfmapping_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/cfb', value => [{ destinationset => $cfdestinationset->{name},
                 timeset => $cftimeset->{name}}] } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test cfmappings");
    $req = HTTP::Request->new('GET', $cfmapping_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test cfmappings");
    $cfmappings = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('cfmappings',$cfmappings,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('cfmappings',$subscriber->{id},$cfmappings,'update',$journals,$journal);
    
    _test_journal_collection('cfmappings',$subscriber->{id},$journals);
    
    return $cfmappings;
    
}


sub test_cftimeset {
    my ($t,$subscriber) = @_;
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
    my @times = ({ year => $year + 1900,
                  month => $mon + 1,
                  mday => $mday,
                  wday => $wday + 1,
                  hour => $hour,
                  minute => $min}) x 3;
    
    $req = HTTP::Request->new('POST', $uri.'/api/cftimesets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "cf_time_set_".($t-1),
        subscriber_id => $subscriber->{id},
        times => \@times,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test cftimeset");
    my $cftimeset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $cftimeset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test cftimeset");
    my $cftimeset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('cftimesets',$cftimeset,$cftimeset->{id});
    _test_journal_options_head('cftimesets',$cftimeset->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('cftimesets',$cftimeset->{id},$cftimeset,'create',$journals);
    _test_journal_options_head('cftimesets',$cftimeset->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $cftimeset_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "cf_time_set_".($t-1).'_put',
        subscriber_id => $subscriber->{id},
        times => \@times,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test cftimeset");
    $req = HTTP::Request->new('GET', $cftimeset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test cftimeset");
    $cftimeset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('cftimesets',$cftimeset,$cftimeset->{id});    
    $journal = _test_journal_top_journalitem('cftimesets',$cftimeset->{id},$cftimeset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $cftimeset_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "cf_time_set_".($t-1).'_patch' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test cftimeset");
    $req = HTTP::Request->new('GET', $cftimeset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test cftimeset");
    $cftimeset = JSON::from_json($res->decoded_content);

    _test_item_journal_link('cftimesets',$cftimeset,$cftimeset->{id});    
    $journal = _test_journal_top_journalitem('cftimesets',$cftimeset->{id},$cftimeset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $cftimeset_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test cftimeset");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('cftimesets',$cftimeset->{id},$cftimeset,'delete',$journals,$journal);
    
    _test_journal_collection('cftimesets',$cftimeset->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/cftimesets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "cf_time_set_".$t,
        subscriber_id => $subscriber->{id},
        times => \@times,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test cftimeset");
    $cftimeset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $cftimeset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test cftimeset");
    $cftimeset = JSON::from_json($res->decoded_content);
    
    return $cftimeset;
    
}

sub test_cfdestinationset {
    my ($t,$subscriber) = @_;
    
    my @destinations = map { { destination => $_,
                           timeout => '10',
                           priority => '1',
                           simple_destination => undef }; } (
                                'voicebox',
                                'fax2mail',
                                'conference',
                                'callingcard',
                                'callthrough',
                                'localuser',
                                'autoattendant',
                                'officehours',
                                'test_destination@example.com');
    
    $req = HTTP::Request->new('POST', $uri.'/api/cfdestinationsets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "cf_destination_set_".($t-1),
        subscriber_id => $subscriber->{id},
        destinations => \@destinations,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test cfdestinationset");
    my $cfdestinationset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test cfdestinationset");
    my $cfdestinationset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('cfdestinationsets',$cfdestinationset,$cfdestinationset->{id});
    _test_journal_options_head('cfdestinationsets',$cfdestinationset->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('cfdestinationsets',$cfdestinationset->{id},$cfdestinationset,'create',$journals);
    _test_journal_options_head('cfdestinationsets',$cfdestinationset->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $cfdestinationset_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "cf_destination_set_".($t-1).'_put',
        subscriber_id => $subscriber->{id},
        destinations => \@destinations,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test cfdestinationset");
    $req = HTTP::Request->new('GET', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test cfdestinationset");
    $cfdestinationset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('cfdestinationsets',$cfdestinationset,$cfdestinationset->{id});    
    $journal = _test_journal_top_journalitem('cfdestinationsets',$cfdestinationset->{id},$cfdestinationset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $cfdestinationset_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "cf_destination_set_".($t-1).'_patch' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test cfdestinationset");
    $req = HTTP::Request->new('GET', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test cfdestinationset");
    $cfdestinationset = JSON::from_json($res->decoded_content);

    _test_item_journal_link('cfdestinationsets',$cfdestinationset,$cfdestinationset->{id});    
    $journal = _test_journal_top_journalitem('cfdestinationsets',$cfdestinationset->{id},$cfdestinationset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test cfdestinationset");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('cfdestinationsets',$cfdestinationset->{id},$cfdestinationset,'delete',$journals,$journal);
    
    _test_journal_collection('cfdestinationsets',$cfdestinationset->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/cfdestinationsets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "cf_destination_set_".$t,
        subscriber_id => $subscriber->{id},
        destinations => \@destinations,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test cfdestinationset");
    $cfdestinationset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test cfdestinationset");
    $cfdestinationset = JSON::from_json($res->decoded_content);
    
    return $cfdestinationset;
    
}


sub test_profilepreferences {
    
    my ($subscriberprofile) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/profilepreferencedefs/');
    $res = $ua->request($req);
    is($res->code, 200, "fetch profilepreferencedefs");
    my $profilepreferencedefs = JSON::from_json($res->decoded_content);

    my $profilepreferences_uri = $uri.'/api/profilepreferences/'.$subscriberprofile->{id};
    $req = HTTP::Request->new('PUT', $profilepreferences_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    my $put_data = {};
    foreach my $attr (keys %$profilepreferencedefs) {
        my $def = $profilepreferencedefs->{$attr};
        my $val = _get_preference_value($attr,$def);
        if (defined $val) {
            $put_data->{$attr} = $val;
        }
    }
    $req->content(JSON::to_json($put_data));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test profilepreferences");
    $req = HTTP::Request->new('GET', $profilepreferences_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test profilepreferences");
    my $profilepreferences = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('profilepreferences',$profilepreferences,$profilepreferences->{id});
    _test_journal_options_head('profilepreferences',$profilepreferences->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('profilepreferences',$profilepreferences->{id},$profilepreferences,'update',$journals);
    _test_journal_options_head('profilepreferences',$profilepreferences->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $profilepreferences_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    my @patch_data = ();
    foreach my $attr (keys %$profilepreferencedefs) {
        my $def = $profilepreferencedefs->{$attr};
        my $val = _get_preference_value($attr,$def);
        if (defined $val) {
            push(@patch_data,{ op => 'replace', path => '/'.$attr, value => $val });
        }
    }
    $req->content(JSON::to_json(\@patch_data));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test profilepreferences");
    $req = HTTP::Request->new('GET', $profilepreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test profilepreferences");
    $profilepreferences = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('profilepreferences',$profilepreferences,$profilepreferences->{id});    
    $journal = _test_journal_top_journalitem('profilepreferences',$profilepreferences->{id},$profilepreferences,'update',$journals,$journal);
    
    _test_journal_collection('profilepreferences',$profilepreferences->{id},$journals);
    
    return $profilepreferences;
    
}


sub test_subscriberprofile {
    my ($t,$profileset) = @_;
    
    $req = HTTP::Request->new('GET', $uri.'/api/subscriberpreferencedefs/');
    $res = $ua->request($req);
    is($res->code, 200, "fetch profilepreferencedefs");
    my $subscriberpreferencedefs = JSON::from_json($res->decoded_content);
    
    my @attributes = ();
    foreach my $attr (keys %$subscriberpreferencedefs) {
        push(@attributes,$attr);
        #my $def = $profilepreferencedefs->{$attr};
        #my $val = _get_preference_value($attr,$def);
        #if (defined $val) {
        #    push(@attributes,$attr);
        #}
    }
    
    $req = HTTP::Request->new('POST', $uri.'/api/subscriberprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "subscriber_profile_".($t-1),
        profile_set_id => $profileset->{id},
        attributes => \@attributes,
        ($mysql_sqlstrict ? (description => '') : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test subscriberprofile");
    my $subscriberprofile_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $subscriberprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriberprofile");
    my $subscriberprofile = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscriberprofiles',$subscriberprofile,$subscriberprofile->{id});
    _test_journal_options_head('subscriberprofiles',$subscriberprofile->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('subscriberprofiles',$subscriberprofile->{id},$subscriberprofile,'create',$journals);
    _test_journal_options_head('subscriberprofiles',$subscriberprofile->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $subscriberprofile_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "subscriber_profile_".($t-1).'_put',
        profile_set_id => $profileset->{id},
        attributes => \@attributes,
        ($mysql_sqlstrict ? (description => '') : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test subscriberprofile");
    $req = HTTP::Request->new('GET', $subscriberprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test subscriberprofile");
    $subscriberprofile = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscriberprofiles',$subscriberprofile,$subscriberprofile->{id});    
    $journal = _test_journal_top_journalitem('subscriberprofiles',$subscriberprofile->{id},$subscriberprofile,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $subscriberprofile_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "subscriber_profile_".($t-1).'_patch' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test subscriberprofile");
    $req = HTTP::Request->new('GET', $subscriberprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test subscriberprofile");
    $subscriberprofile = JSON::from_json($res->decoded_content);

    _test_item_journal_link('subscriberprofiles',$subscriberprofile,$subscriberprofile->{id});    
    $journal = _test_journal_top_journalitem('subscriberprofiles',$subscriberprofile->{id},$subscriberprofile,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $subscriberprofile_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test subscriberprofile");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('subscriberprofiles',$subscriberprofile->{id},$subscriberprofile,'delete',$journals,$journal);
    
    _test_journal_collection('subscriberprofiles',$subscriberprofile->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/subscriberprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "subscriber_profile_".$t,
        profile_set_id => $profileset->{id},
        attributes => \@attributes,
        ($mysql_sqlstrict ? (description => '') : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test subscriberprofile");
    $subscriberprofile_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $subscriberprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriberprofile");
    $subscriberprofile = JSON::from_json($res->decoded_content);
    
    return $subscriberprofile;
    
}



sub test_subscriberprofileset {
    my ($t,$reseller) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/subscriberprofilesets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "subscriber_profile_set_".($t-1),
        reseller_id => $reseller->{id},
        ($mysql_sqlstrict ? (description => '') : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test subscriberprofileset");
    my $subscriberprofileset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $subscriberprofileset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriberprofileset");
    my $subscriberprofileset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscriberprofilesets',$subscriberprofileset,$subscriberprofileset->{id});
    _test_journal_options_head('subscriberprofilesets',$subscriberprofileset->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('subscriberprofilesets',$subscriberprofileset->{id},$subscriberprofileset,'create',$journals);
    _test_journal_options_head('subscriberprofilesets',$subscriberprofileset->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $subscriberprofileset_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "subscriber_profile_set_".($t-1).'_put',
        reseller_id => $reseller->{id},
        ($mysql_sqlstrict ? (description => '') : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test subscriberprofileset");
    $req = HTTP::Request->new('GET', $subscriberprofileset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test subscriberprofileset");
    $subscriberprofileset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscriberprofilesets',$subscriberprofileset,$subscriberprofileset->{id});    
    $journal = _test_journal_top_journalitem('subscriberprofilesets',$subscriberprofileset->{id},$subscriberprofileset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $subscriberprofileset_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "subscriber_profile_set_".($t-1).'_patch' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test subscriberprofileset");
    $req = HTTP::Request->new('GET', $subscriberprofileset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test subscriberprofileset");
    $subscriberprofileset = JSON::from_json($res->decoded_content);

    _test_item_journal_link('subscriberprofilesets',$subscriberprofileset,$subscriberprofileset->{id});    
    $journal = _test_journal_top_journalitem('subscriberprofilesets',$subscriberprofileset->{id},$subscriberprofileset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $subscriberprofileset_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test subscriberprofileset");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('subscriberprofilesets',$subscriberprofileset->{id},$subscriberprofileset,'delete',$journals,$journal);
    
    _test_journal_collection('subscriberprofilesets',$subscriberprofileset->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/subscriberprofilesets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "subscriber_profile_set_".$t,
        reseller_id => $reseller->{id},
        ($mysql_sqlstrict ? (description => '') : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test subscriberprofileset");
    $subscriberprofileset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $subscriberprofileset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriberprofileset");
    $subscriberprofileset = JSON::from_json($res->decoded_content);
    
    return $subscriberprofileset;
    
}







sub test_soundset {
    my ($t,$reseller,$customer) = @_;
    my $test_label = (defined $customer ? '' : 'system ') . "soundset";
    $req = HTTP::Request->new('POST', $uri.'/api/soundsets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => $test_label."_".($t-1),
        reseller_id => $reseller->{id},
        (defined $customer ? (customer_id => $customer->{id}) : ()), #contract_id is overwritten
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test " . $test_label);
    my $soundset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $soundset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test " . $test_label);
    my $soundset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('soundsets',$soundset,$soundset->{id});
    _test_journal_options_head('soundsets',$soundset->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('soundsets',$soundset->{id},$soundset,'create',$journals);
    _test_journal_options_head('soundsets',$soundset->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $soundset_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => $test_label."_".($t-1).'_put',
        reseller_id => $reseller->{id},
        #description => 'put'
        (defined $customer ? (customer_id => $customer->{id}) : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test " . $test_label);
    $req = HTTP::Request->new('GET', $soundset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test " . $test_label);
    $soundset = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('soundsets',$soundset,$soundset->{id});    
    $journal = _test_journal_top_journalitem('soundsets',$soundset->{id},$soundset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $soundset_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => $test_label."_".($t-1)."_patch" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test " . $test_label);
    $req = HTTP::Request->new('GET', $soundset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test " . $test_label);
    $soundset = JSON::from_json($res->decoded_content);

    _test_item_journal_link('soundsets',$soundset,$soundset->{id});    
    $journal = _test_journal_top_journalitem('soundsets',$soundset->{id},$soundset,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $soundset_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test " . $test_label);
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('soundsets',$soundset->{id},$soundset,'delete',$journals,$journal);
    
    _test_journal_collection('soundsets',$soundset->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/soundsets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => $test_label."_".$t,
        reseller_id => $reseller->{id},
        (defined $customer ? (customer_id => $customer->{id}) : ()),
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test " . $test_label);
    $soundset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $soundset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test " . $test_label);
    $soundset = JSON::from_json($res->decoded_content);
    
    return $soundset;
    
}

sub test_subscriberpreferences {
    
    my ($subscriber,$soundset,$contract_soundset) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/subscriberpreferencedefs/');
    $res = $ua->request($req);
    is($res->code, 200, "fetch subscriberpreferencedefs");
    my $subscriberpreferencedefs = JSON::from_json($res->decoded_content);

    my $subscriberpreferences_uri = $uri.'/api/subscriberpreferences/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $subscriberpreferences_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    my $put_data = {};
    foreach my $attr (keys %$subscriberpreferencedefs) {
        my $def = $subscriberpreferencedefs->{$attr};
        my $val = _get_preference_value($attr,$def,$soundset,$contract_soundset);
        if (defined $val) {
            $put_data->{$attr} = $val;
        }
    }
    $req->content(JSON::to_json($put_data));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test subscriberpreferences");
    $req = HTTP::Request->new('GET', $subscriberpreferences_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test subscriberpreferences");
    my $subscriberpreferences = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscriberpreferences',$subscriberpreferences,$subscriberpreferences->{id});
    _test_journal_options_head('subscriberpreferences',$subscriberpreferences->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('subscriberpreferences',$subscriberpreferences->{id},$subscriberpreferences,'update',$journals);
    _test_journal_options_head('subscriberpreferences',$subscriberpreferences->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $subscriberpreferences_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    my @patch_data = ();
    foreach my $attr (keys %$subscriberpreferencedefs) {
        my $def = $subscriberpreferencedefs->{$attr};
        my $val = _get_preference_value($attr,$def,$soundset,$contract_soundset);
        if (defined $val) {
            push(@patch_data,{ op => 'replace', path => '/'.$attr, value => $val });
        }
    }
    $req->content(JSON::to_json(\@patch_data));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test subscriberpreferences");
    $req = HTTP::Request->new('GET', $subscriberpreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test subscriberpreferences");
    $subscriberpreferences = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscriberpreferences',$subscriberpreferences,$subscriberpreferences->{id});    
    $journal = _test_journal_top_journalitem('subscriberpreferences',$subscriberpreferences->{id},$subscriberpreferences,'update',$journals,$journal);
    
    _test_journal_collection('subscriberpreferences',$subscriberpreferences->{id},$journals);
    
    return $subscriberpreferences;
    
}

sub test_customerpreferences {
    
    my ($customer) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/customerpreferencedefs/');
    $res = $ua->request($req);
    is($res->code, 200, "fetch customerpreferencedefs");
    my $customerpreferencedefs = JSON::from_json($res->decoded_content);

    my $customerpreferences_uri = $uri.'/api/customerpreferences/'.$customer->{id};
    $req = HTTP::Request->new('PUT', $customerpreferences_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');    
    my $put_data = {};
    foreach my $attr (keys %$customerpreferencedefs) {
        my $def = $customerpreferencedefs->{$attr};
        my $val = _get_preference_value($attr,$def);
        if (defined $val) {
            $put_data->{$attr} = $val;
        }
    }
    $req->content(JSON::to_json($put_data));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test customerpreferences");
    $req = HTTP::Request->new('GET', $customerpreferences_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test customerpreferences");
    my $customerpreferences = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('customerpreferences',$customerpreferences,$customerpreferences->{id});
    _test_journal_options_head('customerpreferences',$customerpreferences->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('customerpreferences',$customerpreferences->{id},$customerpreferences,'update',$journals);
    _test_journal_options_head('customerpreferences',$customerpreferences->{id},$journal->{id});
    
    $req = HTTP::Request->new('PATCH', $customerpreferences_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    my @patch_data = ();
    foreach my $attr (keys %$customerpreferencedefs) {
        my $def = $customerpreferencedefs->{$attr};
        my $val = _get_preference_value($attr,$def);
        if (defined $val) {
            push(@patch_data,{ op => 'replace', path => '/'.$attr, value => $val });
        }
    }
    $req->content(JSON::to_json(\@patch_data));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test customerpreferences");
    $req = HTTP::Request->new('GET', $customerpreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test customerpreferences");
    $customerpreferences = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('customerpreferences',$customerpreferences,$customerpreferences->{id});    
    $journal = _test_journal_top_journalitem('customerpreferences',$customerpreferences->{id},$customerpreferences,'update',$journals,$journal);
    
    _test_journal_collection('customerpreferences',$customerpreferences->{id},$journals);
    
    return $customerpreferences;
    
}

sub test_billingprofile {
    my ($t,$reseller_id) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile $t",
        handle  => "testprofile$t",
        reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billing profile");
    my $billingprofile_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $billingprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billing profile");
    my $billingprofile = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('billingprofiles',$billingprofile,$billingprofile->{id});
    _test_journal_options_head('billingprofiles',$billingprofile->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('billingprofiles',$billingprofile->{id},$billingprofile,'create',$journals);
    _test_journal_options_head('billingprofiles',$billingprofile->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $billingprofile_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile $t PUT",
        handle  => "testprofile$t",
        reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test billingprofile");
    $req = HTTP::Request->new('GET', $billingprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test billingprofile");
    $billingprofile = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('billingprofiles',$billingprofile,$billingprofile->{id});    
    $journal = _test_journal_top_journalitem('billingprofiles',$billingprofile->{id},$billingprofile,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $billingprofile_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "test profile $t PATCH" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test billingprofile");
    $req = HTTP::Request->new('GET', $billingprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test billingprofile");
    $billingprofile = JSON::from_json($res->decoded_content);

    _test_item_journal_link('billingprofiles',$billingprofile,$billingprofile->{id});    
    $journal = _test_journal_top_journalitem('billingprofiles',$billingprofile->{id},$billingprofile,'update',$journals,$journal);
    
    _test_journal_collection('billingprofiles',$billingprofile->{id},$journals);
    
    return $billingprofile;
    
}

sub test_contract {
    my ($billingprofile,$systemcontact) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $systemcontact->{id},
        type => "reseller",
        billing_profile_id => $billingprofile->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test reseller contract");
    my $contract_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $contract_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test reseller contract");
    my $contract = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('contracts',$contract,$contract->{id});
    _test_journal_options_head('contracts',$contract->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('contracts',$contract->{id},$contract,'create',$journals);
    _test_journal_options_head('contracts',$contract->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $contract_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $systemcontact->{id},
        type => "reseller",
        billing_profile_id => $billingprofile->{id},
        external_id => int(rand(10)),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test reseller contract");
    $req = HTTP::Request->new('GET', $contract_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test reseller contract");
    $contract = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('contracts',$contract,$contract->{id});    
    $journal = _test_journal_top_journalitem('contracts',$contract->{id},$contract,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $contract_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/external_id', value => int(rand(10)) } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test reseller contract");
    $req = HTTP::Request->new('GET', $contract_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test reseller contract");
    $contract = JSON::from_json($res->decoded_content);

    _test_item_journal_link('contracts',$contract,$contract->{id});    
    $journal = _test_journal_top_journalitem('contracts',$contract->{id},$contract,'update',$journals,$journal);
    
    _test_journal_collection('contracts',$contract->{id},$journals);
    
    return $contract;
    
}

sub test_customercontact {
    my ($t,$reseller) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "cust_contact_".($t-1)."_first",
        lastname  => "cust_contact_".($t-1)."_last",
        email     => "cust_contact_".($t-1)."\@custcontact.invalid",
        reseller_id => $reseller->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test customercontact");
    my $customercontact_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $customercontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test customercontact");
    my $customercontact = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('customercontacts',$customercontact,$customercontact->{id});
    _test_journal_options_head('customercontacts',$customercontact->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('customercontacts',$customercontact->{id},$customercontact,'create',$journals);
    _test_journal_options_head('customercontacts',$customercontact->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $customercontact_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        firstname => "cust_contact_".($t-1)."_first_put",
        lastname  => "cust_contact_".($t-1)."_last_put",
        email     => "cust_contact_".($t-1)."_put\@custcontact.invalid",
        reseller_id => $reseller->{id},
        external_id => int(rand(10)),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test customercontact");
    $req = HTTP::Request->new('GET', $customercontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test customercontact");
    $customercontact = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('customercontacts',$customercontact,$customercontact->{id});    
    $journal = _test_journal_top_journalitem('customercontacts',$customercontact->{id},$customercontact,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $customercontact_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/firstname', value => "cust_contact_".($t-1)."_first_patch" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test customercontact");
    $req = HTTP::Request->new('GET', $customercontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test customercontact");
    $customercontact = JSON::from_json($res->decoded_content);

    _test_item_journal_link('customercontacts',$customercontact,$customercontact->{id});    
    $journal = _test_journal_top_journalitem('customercontacts',$customercontact->{id},$customercontact,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $customercontact_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test customercontact");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('customercontacts',$customercontact->{id},$customercontact,'delete',$journals,$journal);
    
    _test_journal_collection('customercontacts',$customercontact->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "cust_contact_".$t."_first",
        lastname  => "cust_contact_".$t."_last",
        email     => "cust_contact_".$t."\@custcontact.invalid",
        reseller_id => $reseller->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test customercontact");
    $customercontact_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $customercontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test customercontact");
    $customercontact = JSON::from_json($res->decoded_content);
    
    return $customercontact;
    
}

sub test_reseller {

    my ($t,$contract) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/resellers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
            contract_id => $contract->{id},
            name => "test reseller $t",
            status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test reseller");
    my $reseller_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $reseller_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test reseller");
    my $reseller = JSON::from_json($res->decoded_content);

    _test_item_journal_link('resellers',$reseller,$reseller->{id});
    _test_journal_options_head('resellers',$reseller->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('resellers',$reseller->{id},$reseller,'create',$journals);
    _test_journal_options_head('resellers',$reseller->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $reseller_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
            contract_id => $contract->{id},
            name => "test reseller $t PUT",
            status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test reseller");
    $req = HTTP::Request->new('GET', $reseller_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test reseller");
    $reseller = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('resellers',$reseller,$reseller->{id});    
    $journal = _test_journal_top_journalitem('resellers',$reseller->{id},$reseller,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $reseller_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "test reseller $t PATCH" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test reseller");
    $req = HTTP::Request->new('GET', $reseller_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test reseller");
    $reseller = JSON::from_json($res->decoded_content);

    _test_item_journal_link('resellers',$reseller,$reseller->{id});    
    $journal = _test_journal_top_journalitem('resellers',$reseller->{id},$reseller,'update',$journals,$journal);
    
    #$req = HTTP::Request->new('DELETE', $reseller_uri);
    #$res = $ua->request($req);
    #is($res->code, 204, "delete POSTed test reseller");
    ##$domain = JSON::from_json($res->decoded_content);
    #
    #$journal = _test_journal_top_journalitem('resellers',$reseller->{id},$reseller,'delete',$journals,$journal);
    _test_journal_collection('resellers',$reseller->{id},$journals);    

    #$req = HTTP::Request->new('POST', $uri.'/api/resellers/');
    #$req->header('Content-Type' => 'application/json');
    #$req->content(JSON::to_json({
    #        contract_id => $contract->{id},
    #        name => "test reseller $t 1",
    #        status => "active",
    #}));
    #$res = $ua->request($req);
    #is($res->code, 201, "POST another test reseller");
    #$reseller_uri = $uri.'/'.$res->header('Location');
    #$req = HTTP::Request->new('GET', $reseller_uri);
    #$res = $ua->request($req);
    #is($res->code, 200, "fetch POSTed test reseller");
    #$reseller = JSON::from_json($res->decoded_content);
    
    my $billingprofile_uri = $uri.'/api/billingprofiles/'.$contract->{billing_profile_id};
    $req = HTTP::Request->new('PATCH', $billingprofile_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => $reseller->{id} } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test billingprofile");
    $req = HTTP::Request->new('GET', $billingprofile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test billingprofile");
    my $billingprofile = JSON::from_json($res->decoded_content);
    
    return ($reseller,$billingprofile);
    
}

sub test_systemcontact {
    my ($t) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "syst_contact_".($t-1)."_first",
        lastname  => "syst_contact_".($t-1)."_last",
        email     => "syst_contact_".($t-1)."\@systcontact.invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test systemcontact");
    my $systemcontact_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $systemcontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test systemcontact");
    my $systemcontact = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('systemcontacts',$systemcontact,$systemcontact->{id});
    _test_journal_options_head('systemcontacts',$systemcontact->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('systemcontacts',$systemcontact->{id},$systemcontact,'create',$journals);
    _test_journal_options_head('systemcontacts',$systemcontact->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $systemcontact_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        firstname => "syst_contact_".($t-1)."_first_put",
        lastname  => "syst_contact_".($t-1)."_last_put",
        email     => "syst_contact_".($t-1)."_put\@systcontact.invalid",
        external_id => int(rand(10)),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test systemcontact");
    $req = HTTP::Request->new('GET', $systemcontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test systemcontact");
    $systemcontact = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('systemcontacts',$systemcontact,$systemcontact->{id});    
    $journal = _test_journal_top_journalitem('systemcontacts',$systemcontact->{id},$systemcontact,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $systemcontact_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/firstname', value => "syst_contact_".($t-1)."_first_patch" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test systemcontact");
    $req = HTTP::Request->new('GET', $systemcontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test systemcontact");
    $systemcontact = JSON::from_json($res->decoded_content);

    _test_item_journal_link('systemcontacts',$systemcontact,$systemcontact->{id});    
    $journal = _test_journal_top_journalitem('systemcontacts',$systemcontact->{id},$systemcontact,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $systemcontact_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test systemcontact");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('systemcontacts',$systemcontact->{id},$systemcontact,'delete',$journals,$journal);
    
    _test_journal_collection('systemcontacts',$systemcontact->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "syst_contact_".$t."_first",
        lastname  => "syst_contact_".$t."_last",
        email     => "syst_contact_".$t."\@systcontact.invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test systemcontact");
    $systemcontact_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $systemcontact_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test systemcontact");
    $systemcontact = JSON::from_json($res->decoded_content);
    
    return $systemcontact;
    
}

sub test_domain {
    my ($t,$reseller) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/domains/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        domain => 'test' . ($t-1) . '.example.org',
        reseller_id => $reseller->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test domain");
    my $domain_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $domain_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test domain");
    my $domain = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('domains',$domain,$domain->{id});
    _test_journal_options_head('domains',$domain->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('domains',$domain->{id},$domain,'create',$journals);
    _test_journal_options_head('domains',$domain->{id},$journal->{id});
    
    $req = HTTP::Request->new('DELETE', $domain_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test domain");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('domains',$domain->{id},$domain,'delete',$journals,$journal);
    
    _test_journal_collection('domains',$domain->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/domains/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        domain => 'test' . $t . '.example.org',
        reseller_id => $reseller->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test domain");
    $domain_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $domain_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test domain");
    $domain = JSON::from_json($res->decoded_content);
    
    return $domain;
    
}

sub test_customer {
    my ($customer_contact,$billing_profile) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $customer_contact->{id},
        type => "sipaccount",
        billing_profile_id => $billing_profile->{id},
        max_subscribers => undef,
        external_id => undef,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test customer");
    my $customer_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $customer_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test customer");
    my $customer = JSON::from_json($res->decoded_content);

    _test_item_journal_link('customers',$customer,$customer->{id});
    _test_journal_options_head('customers',$customer->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('customers',$customer->{id},$customer,'create',$journals);
    _test_journal_options_head('customers',$customer->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $customer_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $customer_contact->{id},
        type => "sipaccount",
        billing_profile_id => $billing_profile->{id}, #$billing_profile_id,
        max_subscribers => undef,
        external_id => int(rand(10)),
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test customer");
    $req = HTTP::Request->new('GET', $customer_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test customer");
    $customer = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('customers',$customer,$customer->{id});    
    $journal = _test_journal_top_journalitem('customers',$customer->{id},$customer,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $customer_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'pending' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test customer");
    $req = HTTP::Request->new('GET', $customer_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test customer");
    $customer = JSON::from_json($res->decoded_content);

    _test_item_journal_link('customers',$customer,$customer->{id});    
    $journal = _test_journal_top_journalitem('customers',$customer->{id},$customer,'update',$journals,$journal);
    
    _test_journal_collection('customers',$customer->{id},$journals);
    
    return $customer;

}

sub test_subscriber {
    my ($t,$customer,$domain) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        domain_id => $domain->{id},
        username => 'test_customer_subscriber_'.($t-1),
        password => 'test_customer_subscriber_password',
        customer_id => $customer->{id},
        #primary_number
        #status => "active",
        #administrative
        #is_pbx_pilot
        #profile_set_id
        #profile_id
        #id
        #alias_numbers => []
        #customer_id - pbxaccount
        #admin
        #pbx_extension
        #is_pbx_group
        #pbx_group_ids => []
        #display_name
        #external_id
        #preferences
        #groups
        
        #status => "active",
        #contact_id => $customer_contact->{id},
        #type => "sipaccount",
        #billing_profile_id => $billing_profile->{id},
        #max_subscribers => undef,
        #external_id => undef,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test subscriber");
    my $subscriber_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $subscriber_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriber");
    my $subscriber = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscribers',$subscriber,$subscriber->{id});
    _test_journal_options_head('subscribers',$subscriber->{id});
    my $journals = {};
    my $journal = _test_journal_top_journalitem('subscribers',$subscriber->{id},$subscriber,'create',$journals);
    _test_journal_options_head('subscribers',$subscriber->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $subscriber_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        domain_id => $domain->{id},
        username => 'test_customer_subscriber_'.($t-1),
        password => => 'test_customer_subscriber_password_PUT',
        customer_id => $customer->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test subscriber");
    $req = HTTP::Request->new('GET', $subscriber_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscribers',$subscriber,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('subscribers',$subscriber->{id},$subscriber,'update',$journals,$journal);
    
    $req = HTTP::Request->new('PATCH', $subscriber_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/password', value => 'test_customer_subscriber_password_PATCH', } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test subscriber");
    $req = HTTP::Request->new('GET', $subscriber_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    
    _test_item_journal_link('subscribers',$subscriber,$subscriber->{id});    
    $journal = _test_journal_top_journalitem('subscribers',$subscriber->{id},$subscriber,'update',$journals,$journal);
    
    $req = HTTP::Request->new('DELETE', $subscriber_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete POSTed test subscriber");
    #$domain = JSON::from_json($res->decoded_content);
    
    $journal = _test_journal_top_journalitem('subscribers',$subscriber->{id},$subscriber,'delete',$journals,$journal);
    
    _test_journal_collection('subscribers',$subscriber->{id},$journals);
    
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        domain_id => $domain->{id},
        username => 'test_customer_subscriber_'.$t,
        password => => 'test_customer_subscriber_password',
        customer_id => $customer->{id},
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST another test subscriber");
    $subscriber_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $subscriber_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    
    return $subscriber;
    
}    

sub _test_item_journal_link {
    my ($resource,$item,$item_id) = @_;
    if (_is_journal_resource_enabled($resource)) {
        ok(exists $item->{_links}, "check existence of _links");
        ok($item->{_links}->{'ngcp:journal'}, "check existence of ngcp:journal link");
        ok($item->{_links}->{'ngcp:journal'}->{href} eq '/api/'.$resource . '/' . $item_id . '/journal/', "check if ngcp:journal link equals '/api/$item_id/journal/'");
    }
}  

sub _test_journal_top_journalitem {
    
    my ($resource,$item_id,$content,$op,$journals,$old_journal) = @_;
    if (_is_journal_resource_enabled($resource)) {
        my $url = $uri.'/api/'.$resource . '/' . $item_id . '/journal/recent';
        if (defined $op) {
            $url .= '?operation=' . $op;
        }
        $req = HTTP::Request->new('GET',$url);
        $res = $ua->request($req);
        if (is($res->code, 200, "check recent '$op' journalitem request")) {
            my $journal = JSON::from_json($res->decoded_content);
            ok(exists $journal->{id}, "check existence of id");
            ok(exists $journal->{operation}, "check existence of operation");
            ok($journal->{operation} eq $op, "check expected journal operation");
            ok(exists $journal->{username}, "check existence of username");
            ok(exists $journal->{timestamp}, "check existence of timestamp");
            ok(exists $journal->{content}, "check existence of content");
            
            ok(exists $journal->{_links}, "check existence of _links");
            #ok(exists $journal->{_embedded}, "check existence of _embedded");
            ok($journal->{_links}->{self}, "check existence of self link");
            ok($journal->{_links}->{collection}, "check existence of collection link");
            ok($journal->{_links}->{'ngcp:'.$resource}, "check existence of ngcp:$resource link");
            ok($journal->{_links}->{'ngcp:'.$resource}->{href} eq '/api/'.$resource . '/' . $item_id, "check if ngcp:$resource link equals '/api/$resource/$item_id'");
        
            if (defined $old_journal) {
                ok($journal->{timestamp} ge $old_journal->{timestamp},"check incremented timestamp");
                ok($journal->{id} > $old_journal->{id},"check incremented journal item id");
            }        
            if (defined $content) {
                my $original = Storable::dclone($content);
                delete $original->{_links};
                #delete $original->{_embedded};
                is_deeply($journal->{content}, $original, "check resource '/api/$resource/$item_id' content deeply");
            }
            if (defined $journals) {
                $journals->{$journal->{_links}->{self}->{href}} = $journal;
            }
            return $journal;
        }
    }
    return undef;
}

sub _test_journal_options_head {
    
    my ($resource,$item_id,$id) = @_;
    if (_is_journal_resource_enabled($resource)) {
        my $url = $uri.'/api/'.$resource . '/' . $item_id . '/journal/';
        if (defined $id) {
            $url .= $id . '/';
        }
        $req = HTTP::Request->new('OPTIONS', $url);
        $res = $ua->request($req);
        is($res->code, 200, "check journal options request");
        #is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-customers", "check Accept-Post header in options response");
        my $opts = JSON::from_json($res->decoded_content);
        my @hopts = split /\s*,\s*/, $res->header('Allow');
        ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
        foreach my $opt(qw( GET HEAD OPTIONS )) {
            ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
            ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
        }
        $req = HTTP::Request->new('HEAD', $url);
        $res = $ua->request($req);
        is($res->code, 200, "check options request");
    }
}

sub _test_journal_collection {
    my ($resource,$item_id,$journals) = @_;
    if (_is_journal_resource_enabled($resource)) {
        my $total_count = (defined $journals ? (scalar keys %$journals) : undef);
        my $nexturi = $uri.'/api/'.$resource . '/' . $item_id . '/journal/?page=1&rows=' . ((not defined $total_count or $total_count <= 2) ? 2 : $total_count - 1);
        do {
            $res = $ua->get($nexturi);
            is($res->code, 200, "fetch journal collection page");
            my $collection = JSON::from_json($res->decoded_content);
            my $selfuri = $uri . $collection->{_links}->{self}->{href};
            is($selfuri, $nexturi, "check _links.self.href of collection");
            my $colluri = URI->new($selfuri);
    
            ok(defined $total_count ? ($collection->{total_count} == $total_count) : ($collection->{total_count} > 0), "check 'total_count' of collection");
    
            my %q = $colluri->query_form;
            ok(exists $q{page} && exists $q{rows}, "check existence of 'page' and 'row' in 'self'");
            my $page = int($q{page});
            my $rows = int($q{rows});
            if($page == 1) {
                ok(!exists $collection->{_links}->{prev}->{href}, "check absence of 'prev' on first page");
            } else {
                ok(exists $collection->{_links}->{prev}->{href}, "check existence of 'prev'");
            }
            if(($collection->{total_count} / $rows) <= $page) {
                ok(!exists $collection->{_links}->{next}->{href}, "check absence of 'next' on last page");
            } else {
                ok(exists $collection->{_links}->{next}->{href}, "check existence of 'next'");
            }
    
            if($collection->{_links}->{next}->{href}) {
                $nexturi = $uri . $collection->{_links}->{next}->{href};
            } else {
                $nexturi = undef;
            }
    
            # TODO: I'd expect that to be an array ref in any case!
            ok(ref $collection->{_links}->{'ngcp:journal'} eq "ARRAY", "check if 'ngcp:journal' is array");
            
            my $page_journals = {};
    
            foreach my $journal (@{ $collection->{_links}->{'ngcp:journal'} }) {
                #delete $customers{$c->{href}};
                ok(exists $journals->{$journal->{href}},"check page journal item link");
                
                $req = HTTP::Request->new('GET',$uri . $journal->{href});
                $res = $ua->request($req);
                is($res->code, 200, "fetch page journal item");            
                
                my $original = delete $journals->{$journal->{href}};
                $page_journals->{$original->{id}} = $original;
            }
            foreach my $journal (@{ $collection->{_embedded}->{'ngcp:journal'} }) {
                ok(exists $page_journals->{$journal->{id}},"check existence of linked journal item among embedded");
                my $original = delete $page_journals->{$journal->{id}};
                delete $original->{content};
                is_deeply($original,$journal,"compare created and embedded journal item deeply");
            }
            ok((scalar keys $page_journals) == 0,"check if all embedded journal items are linked");
                 
        } while($nexturi);
            
        ok((scalar keys $journals) == 0,"check if journal collection lists all created journal items" . (defined $total_count ? " ($total_count)" : ''));
    }
}

sub _is_journal_resource_enabled {
    my ($resource) = @_;   
    my $cfg = NGCP::Panel::Utils::Journal::get_journal_resource_config(\%config,$resource);
    if (not $cfg->{journal_resource_enabled}) {
        diag("'api/$resource' journal resource disabled, skipping tests");
    }
    return ($enable_journal_tests && $cfg->{journal_resource_enabled});
}

sub _get_preference_value {
    my ($attr,$def,$soundset,$contract_soundset) = @_;
     if (exists $def->{data_type} and not $def->{read_only} and $def->{max_occur} > 0) {
        my $val_code = undef;
        if ($attr eq 'sound_set') {
            $val_code = sub { return $soundset->{name}; };
        } elsif ($attr eq 'contract_sound_set') {
            $val_code = sub { return $contract_soundset->{name}; };            
        } else {
            if ($def->{data_type} eq 'int') {
                $val_code = sub { return 1; };
            } elsif ($def->{data_type} eq 'string') {
                $val_code = sub { return 'test'; };
            }
        }
        if (defined $val_code) {
            if ($def->{max_occur} > 1) {
                my @ary = map { &$_(); } (($val_code) x $def->{max_occur});
                return \@ary;
            } else {
                return &$val_code;   
            }
        }
    }
    return undef;
}

# vim: set tabstop=4 expandtab:
