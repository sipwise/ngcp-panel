#use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $is_local_env = 0;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
my $user = $ENV{API_USER} // 'administrator';
my $pass = $ENV{API_PASS} // 'administrator';
$ua->credentials($netloc, "api_admin_http", $user, $pass);

#$ua->add_handler("request_send",  sub {
#    my ($request, $ua, $h) = @_;
#    print $request->method . ' ' . $request->uri . "\n" . ($request->content ? $request->content . "\n" : '') unless $request->header('authorization');
#    return undef;
#});
#$ua->add_handler("response_done", sub {
#    my ($response, $ua, $h) = @_;
#    print $response->decoded_content . "\n" if $response->code != 401;
#    return undef;
#});

my $t = time;
my $reseller_id = 1;

$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    domain => 'test' . $t . '.example.org',
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create test domain");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch created test domain");
my $domain = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create test billing profile");
my $billing_profile_id = $res->header('Location');
$billing_profile_id =~ s/^.+\/(\d+)$/$1/;

$req = HTTP::Request->new('POST', $uri.'/api/subscriberprofilesets/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    name => "subscriber_profile_set_".$t,
    reseller_id => $reseller_id,
    description => "subscriber_profile_set_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofileset");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofileset");
my $subscriberprofileset = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('GET', $uri.'/api/subscriberpreferencedefs/');
$res = $ua->request($req);
is($res->code, 200, "fetch profilepreferencedefs");
my $subscriberpreferencedefs = JSON::from_json($res->decoded_content);

my @subscriber_profile_attributes = ();
foreach my $attr (keys %$subscriberpreferencedefs) {
    push(@subscriber_profile_attributes,$attr);
}

$req = HTTP::Request->new('POST', $uri.'/api/subscriberprofiles/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    name => "subscriber_profile_".$t,
    profile_set_id => $subscriberprofileset->{id},
    attributes => \@subscriber_profile_attributes,
    description => "subscriber_profile_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofile");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofile");
my $subscriberprofile = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    firstname => "cust_contact_first",
    lastname  => "cust_contact_last",
    email     => "cust_contact\@custcontact.invalid",
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create test customer contact");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch test customer contact");
my $custcontact = JSON::from_json($res->decoded_content);

my %subscriber_map = ();
my %customer_map = ();

#goto SKIP;
{
    my $customer = _create_customer(
        type => "sipaccount",
        );
    my $subscriber = _create_subscriber($customer,
        primary_number => { cc => 888, ac => '1'.(scalar keys %subscriber_map), sn => $t },
        profile_id => $subscriberprofile->{id},
        profile_set_id => $subscriberprofileset->{id},
        );

    my $call_forwards = set_callforwards($subscriber,{ cfu => {
                destinations => [
                    { destination => "5678" },
                    { destination => "autoattendant", },
                ],
            }});
    $call_forwards = set_callforwards($subscriber,{ cfu => {
                destinations => [
                    { destination => "5678" },
                ],
            }});
    _check_event_history("events generated using /api/callforwards: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr" },
        { subscriber_id => $subscriber->{id}, type => "end_ivr" },
    ]);
}

#$t = time;

SKIP:
{

    my $customer = _create_customer(
        type => "sipaccount",
        );
    my $subscriber = _create_subscriber($customer,
        primary_number => { cc => 888, ac => '2'.(scalar keys %subscriber_map), sn => $t },
        profile_id => $subscriberprofile->{id},
        profile_set_id => $subscriberprofileset->{id},
        );

    my $destinationset_1 = _create_cfdestinationset($subscriber,"dest1_$t",[{ destination => "1234",
        timeout => '10',
        priority => '1',
        simple_destination => undef },{ destination => "autoattendant",
        timeout => '10',
        priority => '1',
        simple_destination => undef }
    ]);
    my $destinationset_2 = _create_cfdestinationset($subscriber,"dest2_$t",[{ destination => "1234",
        timeout => '10',
        priority => '1',
        simple_destination => undef },{ destination => "autoattendant",
        timeout => '10',
        priority => '1',
        simple_destination => undef }
    ]);

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
    my $timeset = _create_cftimeset($subscriber,[{ year => $year + 1900,
                  month => $mon + 1,
                  mday => $mday,
                  wday => $wday + 1,
                  hour => $hour,
                  minute => $min}]);
    my $mappings = _create_cfmapping($subscriber,{
        #cfb => [{ destinationset => $cfdestinationset->{name},
        #         timeset => $cftimeset->{name}}],
        #cfna => [{ destinationset => $cfdestinationset->{name},
        #         timeset => $cftimeset->{name}}],
        #cft => [{ destinationset => $cfdestinationset->{name},
        #         timeset => $cftimeset->{name}}],
        cfb => [],
        cfna => [],
        cft => [{ destinationset => $destinationset_1->{name},
                 timeset => $timeset->{name}}],
        cfu => [{ destinationset => $destinationset_2->{name},
                 timeset => $timeset->{name}}],
        });

    #1. update destination set:
    $destinationset_1 = _update_cfdestinationset($destinationset_1,[{ destination => "1234",
        timeout => '10',
        priority => '1',
        simple_destination => undef },
    ]);
    _check_event_history("events generated by updating /api/cfdestinationsets: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr" },
        { subscriber_id => $subscriber->{id}, type => "start_ivr" },
        { subscriber_id => $subscriber->{id}, type => "end_ivr" },
    ]);
    #2. update cfmappings:
    $mappings = _update_cfmapping($subscriber,"cfu",[]);
    _check_event_history("events generated by updating /api/cfmappings: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr" },
        { subscriber_id => $subscriber->{id}, type => "start_ivr" },
        { subscriber_id => $subscriber->{id}, type => "end_ivr" },
        { subscriber_id => $subscriber->{id}, type => "end_ivr" },
    ]);

}

sub _create_cfmapping {
    my ($subscriber,$mappings) = @_;

    my $cfmapping_uri = $uri.'/api/cfmappings/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $cfmapping_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($mappings));
    $res = $ua->request($req);
    is($res->code, 200, "create test cfmappings");
    $req = HTTP::Request->new('GET', $cfmapping_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test cfmappings");
    return JSON::from_json($res->decoded_content);
}

sub _update_cfmapping {
    my ($subscriber,$cf_type,$mapping) = @_;
    my $cfmapping_uri = $uri.'/api/cfmappings/'.$subscriber->{id};
    $req = HTTP::Request->new('PATCH', $cfmapping_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/'.$cf_type, value => $mapping } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "update test cfmappings");
    $req = HTTP::Request->new('GET', $cfmapping_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch updated test cfmappings");
    return JSON::from_json($res->decoded_content);
}

sub _create_cftimeset {
    my ($subscriber,$times) = @_;

    $req = HTTP::Request->new('POST', $uri.'/api/cftimesets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "cf_time_set_".$t,
        subscriber_id => $subscriber->{id},
        times => \@times,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test cftimeset");
    my $cftimeset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $cftimeset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch created test cftimeset");
    return JSON::from_json($res->decoded_content);

}

sub _create_cfdestinationset {
    my ($subscriber,$name,$destinations) = @_;

    $req = HTTP::Request->new('POST', $uri.'/api/cfdestinationsets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => $name,
        subscriber_id => $subscriber->{id},
        destinations => $destinations,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test cfdestinationset");
    my $cfdestinationset_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch created test cfdestinationset");
    return JSON::from_json($res->decoded_content);

}

sub _update_cfdestinationset {
    my ($destinationset,$destinations) = @_;
    my $cfdestinationset_uri = $uri.'/api/cfdestinationsets/'.$destinationset->{id};
    $req = HTTP::Request->new('PATCH', $cfdestinationset_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/destinations', value => $destinations } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "update test cfdestinationset");
    $req = HTTP::Request->new('GET', $cfdestinationset_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch updated test cfdestinationset");
    return JSON::from_json($res->decoded_content);

}

sub set_callforwards {
    my ($subscriber,$call_forwards) = @_;

    my $callforward_uri = $uri.'/api/callforwards/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $callforward_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($call_forwards));
    $res = $ua->request($req);
    is($res->code, 200, "set test callforwards");
    $req = HTTP::Request->new('GET', $callforward_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test callforwards");
    return JSON::from_json($res->decoded_content);

}

sub _get_subscriber {

    my ($subscriber) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/subscribers/'.$subscriber->{id});
    $res = $ua->request($req);
    is($res->code, 200, "fetch test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    $subscriber_map{$subscriber->{id}} = $subscriber;
    return $subscriber;

}

sub _create_subscriber {

    my ($customer,@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        domain_id => $domain->{id},
        username => 'subscriber_' . (scalar keys %subscriber_map) . '_'.$t,
        password => 'subscriber_password',
        customer_id => $customer->{id},
        #status => "active",
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test subscriber");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test subscriber");
    my $subscriber = JSON::from_json($res->decoded_content);
    $subscriber_map{$subscriber->{id}} = $subscriber;
    return $subscriber;

}

sub _update_subscriber {

    my ($subscriber,@further_opts) = @_;
    $req = HTTP::Request->new('PUT', $uri.'/api/subscribers/'.$subscriber->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        %$subscriber,
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "update test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    $subscriber_map{$subscriber->{id}} = $subscriber;
    return $subscriber;

}

sub _create_customer {

    my (@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        billing_profile_id => $billing_profile_id,
        max_subscribers => undef,
        external_id => undef,
        #status => "active",
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test customer");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test customer");
    my $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = $customer;
    return $customer;

}


sub _check_event_history {

    my ($label,$subscriber_id,$type,$expected_events) = @_;
    if (defined $subscriber_id) {
        $subscriber_id = '&subscriber_id=' . $subscriber_id;
    } else {
        $subscriber_id = '';
    }
    if (defined $type) {
        $type = '&type=' . $type;
    } else {
        $type = '';
    }

    my $total_count = (scalar @$expected_events);
    my $i = 0;
    my $ok = 1;
    my @events = ();
    my @requests = ();
    my $last_request;
    $last_request = _req_to_debug($req) if $req;
    my $nexturi = $uri.'/api/events/?page=1&rows=10&order_by_direction=asc&order_by=id'.$subscriber_id.$type;
    do {
        $req = HTTP::Request->new('GET',$nexturi);
        $res = $ua->request($req);
        is($res->code, 200, $label . "fetch events collection page");
        push(@requests,_req_to_debug($req));
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        my $colluri = URI->new($selfuri);

        $ok = ok($collection->{total_count} == $total_count, $label . "check 'total_count' of collection") && $ok;

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        $collection->{_embedded}->{'ngcp:events'} = [
            $collection->{_embedded}->{'ngcp:events'}
        ] if "HASH" eq ref $collection->{_embedded}->{'ngcp:events'};

        my $page_items = {};

        foreach my $event (@{ $collection->{_embedded}->{'ngcp:events'} }) {
            $ok = _compare_event($event,$expected_events->[$i],$label) && $ok;
            delete $event->{'_links'};
            push(@events,$event);
            $i++
        }

    } while($nexturi);

    ok($i == $total_count,$label . "check if all expected items are listed");
    diag(Dumper({last_request => $last_request, collection_requests => \@requests, result => \@events})) if !$ok;

}

sub _compare_event {

    my ($got,$expected,$label) = @_;

    my $ok = 1;

    if ($expected->{id}) {
        $ok = is($got->{id},$expected->{id},$label . "check event " . $got->{id} . " id") && $ok;
    }

    if ($expected->{subscriber_id}) {
        $ok = is($got->{subscriber_id},$expected->{subscriber_id},$label . "check event " . $got->{id} . " subscriber_id") && $ok;
    }

    if ($expected->{type}) {
        $ok = is($got->{type},$expected->{type},$label . "check event " . $got->{id} . " type '".$expected->{type}."'") && $ok;
    }

    return $ok;

}

sub _req_to_debug {
    my $request = shift;
    return { request => $request->method . " " . $request->uri,
            headers => $request->headers };
}

sub _get_query_string {
    my ($filters) = @_;
    my $query = '';
    foreach my $param (keys %$filters) {
        if (length($query) == 0) {
            $query .= '?';
        } else {
            $query .= '&';
        }
        $query .= $param . '=' . $filters->{$param};
    }
    return $query;
};

done_testing;
