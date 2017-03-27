use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;
use Data::Dumper;

my $is_local_env = 1;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

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
    name => "subscriber_profile_1_set_".$t,
    reseller_id => $reseller_id,
    description => "subscriber_profile_1_set_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofileset 1");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofileset 1");
my $subscriberprofile1set = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/subscriberprofilesets/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    name => "subscriber_profile_2_set_".$t,
    reseller_id => $reseller_id,
    description => "subscriber_profile_2_set_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofileset 2");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofileset 2");
my $subscriberprofile2set = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/subscriberprofilesets/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    name => "subscriber_profile_3_set_".$t,
    reseller_id => $reseller_id,
    description => "subscriber_profile_3_set_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofileset 3");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofileset 3");
my $subscriberprofile3set = JSON::from_json($res->decoded_content);

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
    name => "subscriber_profile_1_".$t,
    profile_set_id => $subscriberprofile1set->{id},
    attributes => \@subscriber_profile_attributes,
    description => "subscriber_profile_1_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofile 1");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofile 1");
my $subscriberprofile1 = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/subscriberprofiles/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    name => "subscriber_profile_2_".$t,
    profile_set_id => $subscriberprofile2set->{id},
    attributes => \@subscriber_profile_attributes,
    description => "subscriber_profile_2_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofile 2");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofile 2");
my $subscriberprofile2 = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/subscriberprofiles/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    name => "subscriber_profile_3_".$t,
    profile_set_id => $subscriberprofile3set->{id},
    attributes => \@subscriber_profile_attributes,
    description => "subscriber_profile_3_description_".$t,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test subscriberprofile 3");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test subscriberprofile 3");
my $subscriberprofile3 = JSON::from_json($res->decoded_content);

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
{ #end_ivr:
    my $customer = _create_customer(
        type => "sipaccount",
        );
    my $cc = 800;
    my $ac = '1'.(scalar keys %subscriber_map);
    my $sn = $t;
    my $subscriber = _create_subscriber($customer,
        primary_number => { cc => $cc, ac => $ac, sn => $sn },
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

#SKIP:
{ #end_ivr:
    my $customer = _create_customer(
        type => "sipaccount",
        );
    my $cc = 800;
    my $ac = '1'.(scalar keys %subscriber_map);
    my $sn = $t;
    my $aliases = [
            { cc => $cc, ac => $ac, sn => $sn.'0001' },
            { cc => $cc, ac => $ac, sn => $sn.'0002' },
        ];
    my $subscriber = _create_subscriber($customer,
        primary_number => { cc => $cc, ac => $ac, sn => $sn },
        alias_numbers => $aliases,
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
    _check_event_history("multiple alaises - events generated using /api/callforwards: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
    ]);
}

#$t = time;

#SKIP:
{ #end_ivr:

    my $customer = _create_customer(
        type => "sipaccount",
        );
    my $cc = 800;
    my $ac = '2'.(scalar keys %subscriber_map);
    my $sn = $t;
    my $aliases = [
            { cc => $cc, ac => $ac, sn => $sn.'0001' },
            { cc => $cc, ac => $ac, sn => $sn.'0002' },
        ];
    my $subscriber = _create_subscriber($customer,
        primary_number => { cc => $cc, ac => $ac, sn => $sn },
        alias_numbers => $aliases,
    );
    #my $subscriber = _create_subscriber($customer,
    #    primary_number => { cc => 888, ac => '2'.(scalar keys %subscriber_map), sn => $t },
    #    alias_numbers => $aliases,
    #    );

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
        cfs => [],
        });

    #1. update destination set:
    $destinationset_1 = _update_cfdestinationset($destinationset_1,[{ destination => "1234",
        timeout => '10',
        priority => '1',
        simple_destination => undef },
    ]);
    _check_event_history("multiple alaises - events generated by updating /api/cfdestinationsets: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
    ]);
    #2. update cfmappings:
    $mappings = _update_cfmapping($subscriber,"cfu",[]);
    _check_event_history("multiple alaises - events generated by updating /api/cfmappings: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
    ]);

}

#SKIP:
{ #end_ivr:
    my $customer = _create_customer(
        type => "sipaccount",
        );
    my $cc = 800;
    my $ac = '3'.(scalar keys %subscriber_map);
    my $sn = $t;
    my $aliases = [
            { cc => $cc, ac => $ac, sn => $sn.'0001' },
            { cc => $cc, ac => $ac, sn => $sn.'0002' },
        ];
    my $subscriber = _create_subscriber($customer,
        primary_number => { cc => $cc, ac => $ac, sn => $sn },
        alias_numbers => $aliases,
    );

    my $call_forwards = set_callforwards($subscriber,{ cfu => {
                destinations => [
                    { destination => "5678" },
                    { destination => "autoattendant", },
                ],
            }});
    _update_subscriber($subscriber, status => 'terminated');
    _check_event_history("multiple alaises - events generated when terminating the subscriber: ",$subscriber->{id},"%ivr",[
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "start_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn} },
        { subscriber_id => $subscriber->{id}, type => "end_ivr", non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn} },
    ]);
}

#SKIP:
#cloudpbx = 0 only
#{ #pilot_primary_number, primary_number:
#
#    my $customer = _create_customer(
#        type => "pbxaccount",
#        );
#    my $cc = "888";
#    my $pilot_ac = undef; #'3'.(scalar keys %subscriber_map);
#    my $pilot_sn = $t.(scalar keys %subscriber_map);
#    my $pilot_subscriber = _create_subscriber($customer,
#        primary_number => { cc => $cc, ac => $pilot_ac, sn => $pilot_sn },
#        is_pbx_pilot => JSON::true,
#        profile_id => $subscriberprofile1->{id},
#        profile_set_id => $subscriberprofile1set->{id},
#        );
#    my $ac = undef; #'3'.(scalar keys %subscriber_map);
#    my $sn = ($t+1).(scalar keys %subscriber_map);
#    my $subscriber = _create_subscriber($customer,
#        primary_number => { cc => $cc, ac => $ac, sn => $sn },
#        profile_id => $subscriberprofile1->{id},
#        profile_set_id => $subscriberprofile1set->{id},
#        );
#    #_update_subscriber($subscriber,
#    _check_event_history("start_profile when creating a pbx pilot subscriber: ",$pilot_subscriber->{id},"start_profile",[
#        { subscriber_id => $pilot_subscriber->{id}, type => "start_profile",
#          subscriber_profile_id => $subscriberprofile1->{id}, subscriber_profile_name => $subscriberprofile1->{name},
#          subscriber_profile_set_id => $subscriberprofile1set->{id}, subscriber_profile_set_name => $subscriberprofile1set->{name},
#          primary_number_cc => $cc, primary_number_ac => $pilot_ac, primary_number_sn => $pilot_sn,
#          pilot_subscriber_id => $pilot_subscriber->{id},
#          pilot_subscriber_profile_id => $subscriberprofile1->{id}, pilot_subscriber_profile_name => $subscriberprofile1->{name},
#          pilot_subscriber_profile_set_id => $subscriberprofile1set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile1set->{name},
#          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $pilot_ac, pilot_primary_number_sn => $pilot_sn,
#        },
#    ]);
#    _check_event_history("start_profile when creating a pbx subscriber: ",$subscriber->{id},"start_profile",[
#        { subscriber_id => $subscriber->{id}, type => "start_profile",
#          subscriber_profile_id => $subscriberprofile1->{id}, subscriber_profile_name => $subscriberprofile1->{name},
#          subscriber_profile_set_id => $subscriberprofile1set->{id}, subscriber_profile_set_name => $subscriberprofile1set->{name},
#          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn,
#          pilot_subscriber_id => $pilot_subscriber->{id},
#          pilot_subscriber_profile_id => $subscriberprofile1->{id}, pilot_subscriber_profile_name => $subscriberprofile1->{name},
#          pilot_subscriber_profile_set_id => $subscriberprofile1set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile1set->{name},
#          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $pilot_ac, pilot_primary_number_sn => $pilot_sn,
#        },
#    ]);
#
#}

#SKIP:
{ #pilot_primary_number, primary_number, pilot_first_non_primary_alias, susbcriber_first_non_primary_alias:

    my $customer = _create_customer(
        type => "pbxaccount",
        );
    my $cc = "888";
    my $ac = 5; #'3'.(scalar keys %subscriber_map);
    my $sn = $t.(scalar keys %subscriber_map);
    my $pilot_aliases = [
        { cc => $cc, ac => $ac, sn => $sn.'0001' },
        { cc => $cc, ac => $ac, sn => $sn.'0002' },
        #{ cc => $cc, ac => $ac, sn => $sn.'0003' },
        #{ cc => $cc, ac => $ac, sn => $sn.'0004' },
        #{ cc => $cc, ac => $ac, sn => $sn.'0005' },
    ];
    my $pilot_subscriber = _create_subscriber($customer,
        primary_number => { cc => $cc, ac => $ac, sn => $sn },
        alias_numbers => $pilot_aliases,
        profile_id => $subscriberprofile1->{id},
        profile_set_id => $subscriberprofile1set->{id},
        is_pbx_pilot => JSON::true,
        );
    my $ext = '1';
    my $aliases = [
        { cc => $cc, ac => $ac, sn => $sn.'0003' },
        { cc => $cc, ac => $ac, sn => $sn.'0004' },
        #{ cc => $cc, ac => $ac, sn => $sn.'0006' },
    ];
    #make sure cloudpbx = 1
    my $subscriber = _create_subscriber($customer,
        pbx_extension => $ext,
        alias_numbers => $aliases,
        profile_id => $subscriberprofile1->{id},
        profile_set_id => $subscriberprofile1set->{id},
        );
    #_update_subscriber($subscriber,
    my %pilot_event = (
        subscriber_id => $pilot_subscriber->{id},
          subscriber_profile_id => $subscriberprofile1->{id}, subscriber_profile_name => $subscriberprofile1->{name},
          subscriber_profile_set_id => $subscriberprofile1set->{id}, subscriber_profile_set_name => $subscriberprofile1set->{name},
          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn,
          pilot_subscriber_id => $pilot_subscriber->{id},
          pilot_subscriber_profile_id => $subscriberprofile1->{id}, pilot_subscriber_profile_name => $subscriberprofile1->{name},
          pilot_subscriber_profile_set_id => $subscriberprofile1set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile1set->{name},
          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $ac, pilot_primary_number_sn => $sn,

          first_non_primary_alias_username_before => undef,
          first_non_primary_alias_username_after => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_before => undef,
          pilot_first_non_primary_alias_username_after => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},

          primary_alias_username_before => $cc.$ac.$sn,
          primary_alias_username_after => $cc.$ac.$sn,
          pilot_primary_alias_username_before => $cc.$ac.$sn,
          pilot_primary_alias_username_after => $cc.$ac.$sn,
    );
    _check_event_history("start_profile when creating a pbx pilot subscriber w alias: ",$pilot_subscriber->{id},"%profile",[
        { %pilot_event,

          type => "start_profile",
          old_status => '',
          new_status => $subscriberprofile1->{id},

          non_primary_alias_username => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
        },
        { %pilot_event,

          type => "start_profile",
          old_status => '',
          new_status => $subscriberprofile1->{id},

          non_primary_alias_username => $pilot_aliases->[1]->{cc}.$pilot_aliases->[1]->{ac}.$pilot_aliases->[1]->{sn},
        },
        #{ %pilot_event,

        #  type => "start_profile",

        #  non_primary_alias_username => $pilot_aliases->[2]->{cc}.$pilot_aliases->[2]->{ac}.$pilot_aliases->[2]->{sn},
        #},
    ]);
    my %subscriber_event = (
        subscriber_id => $subscriber->{id},
          subscriber_profile_id => $subscriberprofile1->{id}, subscriber_profile_name => $subscriberprofile1->{name},
          subscriber_profile_set_id => $subscriberprofile1set->{id}, subscriber_profile_set_name => $subscriberprofile1set->{name},
          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn.$ext,
          pilot_subscriber_id => $pilot_subscriber->{id},
          pilot_subscriber_profile_id => $subscriberprofile1->{id}, pilot_subscriber_profile_name => $subscriberprofile1->{name},
          pilot_subscriber_profile_set_id => $subscriberprofile1set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile1set->{name},
          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $ac, pilot_primary_number_sn => $sn,

          first_non_primary_alias_username_before => undef,
          first_non_primary_alias_username_after => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_before => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_after => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},

          primary_alias_username_before => $cc.$ac.$sn.$ext,
          primary_alias_username_after => $cc.$ac.$sn.$ext,
          pilot_primary_alias_username_before => $cc.$ac.$sn,
          pilot_primary_alias_username_after => $cc.$ac.$sn,

    );
    _check_event_history("start_profile when creating a pbx extension subscriber w alias: ",$subscriber->{id},"%profile",[
        { %subscriber_event,

          type => "start_profile",
          old_status => '',
          new_status => $subscriberprofile1->{id},

          non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn},
        },
        { %subscriber_event,

          type => "start_profile",
          old_status => '',
          new_status => $subscriberprofile1->{id},

          non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn},
        },

    ]);

    my $new_aliases = [
        { cc => $cc, ac => $ac, sn => $sn.'0004' },
        { cc => $cc, ac => $ac, sn => $sn.'0005' },
    ];
    _update_subscriber($subscriber,
        alias_numbers => $new_aliases,
        profile_id => $subscriberprofile2->{id},
        profile_set_id => $subscriberprofile2set->{id},
    );
    %subscriber_event = (
        subscriber_id => $subscriber->{id},
          subscriber_profile_id => $subscriberprofile2->{id}, subscriber_profile_name => $subscriberprofile2->{name},
          subscriber_profile_set_id => $subscriberprofile2set->{id}, subscriber_profile_set_name => $subscriberprofile2set->{name},
          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn.$ext,
          pilot_subscriber_id => $pilot_subscriber->{id},
          pilot_subscriber_profile_id => $subscriberprofile1->{id}, pilot_subscriber_profile_name => $subscriberprofile1->{name},
          pilot_subscriber_profile_set_id => $subscriberprofile1set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile1set->{name},
          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $ac, pilot_primary_number_sn => $sn,

          first_non_primary_alias_username_before => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn},
          first_non_primary_alias_username_after => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_before => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_after => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},

          primary_alias_username_before => $cc.$ac.$sn.$ext,
          primary_alias_username_after => $cc.$ac.$sn.$ext,
          pilot_primary_alias_username_before => $cc.$ac.$sn,
          pilot_primary_alias_username_after => $cc.$ac.$sn,
    );
    _check_event_history("start/update/end_profile when updating a pbx extension subscriber w alias: ",$subscriber->{id},"%profile",[
        {},{},
        { %subscriber_event,

          type => "update_profile",
          old_status => $subscriberprofile1->{id},
          new_status => $subscriberprofile2->{id},

          non_primary_alias_username => $aliases->[1]->{cc}.$aliases->[1]->{ac}.$aliases->[1]->{sn},
        },
        { %subscriber_event,

          type => "start_profile",
          old_status => '',
          new_status => $subscriberprofile2->{id},

          non_primary_alias_username => $new_aliases->[1]->{cc}.$new_aliases->[1]->{ac}.$new_aliases->[1]->{sn},
        },
        { %subscriber_event,

          type => "end_profile",
          old_status => $subscriberprofile1->{id},
          new_status => '',

          non_primary_alias_username => $aliases->[0]->{cc}.$aliases->[0]->{ac}.$aliases->[0]->{sn},
        },
    ]);

    my $new_pilot_aliases = [
        { cc => $cc, ac => $ac, sn => $sn.'0002' },
        { cc => $cc, ac => $ac, sn => $sn.'0003' },
    ];
    _update_subscriber($pilot_subscriber,
        alias_numbers => $new_pilot_aliases,
        profile_id => $subscriberprofile3->{id},
        profile_set_id => $subscriberprofile3set->{id},
    );
    my %pilot_event = (
        subscriber_id => $pilot_subscriber->{id},
          subscriber_profile_id => $subscriberprofile3->{id}, subscriber_profile_name => $subscriberprofile3->{name},
          subscriber_profile_set_id => $subscriberprofile3set->{id}, subscriber_profile_set_name => $subscriberprofile3set->{name},
          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn,
          pilot_subscriber_id => $pilot_subscriber->{id},
          pilot_subscriber_profile_id => $subscriberprofile3->{id}, pilot_subscriber_profile_name => $subscriberprofile3->{name},
          pilot_subscriber_profile_set_id => $subscriberprofile3set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile3set->{name},
          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $ac, pilot_primary_number_sn => $sn,

          first_non_primary_alias_username_before => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
          first_non_primary_alias_username_after => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_before => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_after => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},

          primary_alias_username_before => $cc.$ac.$sn,
          primary_alias_username_after => $cc.$ac.$sn,
          pilot_primary_alias_username_before => $cc.$ac.$sn,
          pilot_primary_alias_username_after => $cc.$ac.$sn,

    );
    _check_event_history("start/update/end_profile when updating a pbx pilot subscriber w alias: ",$pilot_subscriber->{id},"%profile",[
        {},{},
        { %pilot_event,

          type => "update_profile",
          old_status => $subscriberprofile1->{id},
          new_status => $subscriberprofile3->{id},

          non_primary_alias_username => $pilot_aliases->[1]->{cc}.$pilot_aliases->[1]->{ac}.$pilot_aliases->[1]->{sn},
        },
        { %pilot_event,

          type => "start_profile",
          old_status => '',
          new_status => $subscriberprofile3->{id},

          non_primary_alias_username => $new_pilot_aliases->[1]->{cc}.$new_pilot_aliases->[1]->{ac}.$new_pilot_aliases->[1]->{sn},
        },
        { %pilot_event,

          type => "end_profile",
          old_status => $subscriberprofile1->{id},
          new_status => '',

          non_primary_alias_username => $pilot_aliases->[0]->{cc}.$pilot_aliases->[0]->{ac}.$pilot_aliases->[0]->{sn},
        },
    ]);

    _update_subscriber($subscriber, status => 'terminated');
    %subscriber_event = (
    subscriber_id => $subscriber->{id},
          subscriber_profile_id => $subscriberprofile2->{id}, subscriber_profile_name => $subscriberprofile2->{name},
          subscriber_profile_set_id => $subscriberprofile2set->{id}, subscriber_profile_set_name => $subscriberprofile2set->{name},
          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn.$ext,
          pilot_subscriber_id => $pilot_subscriber->{id},
          pilot_subscriber_profile_id => $subscriberprofile3->{id}, pilot_subscriber_profile_name => $subscriberprofile3->{name},
          pilot_subscriber_profile_set_id => $subscriberprofile3set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile3set->{name},
          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $ac, pilot_primary_number_sn => $sn,

          first_non_primary_alias_username_before => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
          first_non_primary_alias_username_after => undef,
          pilot_first_non_primary_alias_username_before => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
          #would be this:
          pilot_first_non_primary_alias_username_after => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
          #but since api termination always returns aliases to the pilot:
          #pilot_first_non_primary_alias_username_after => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
          #pilot_first_non_primary_alias_username_after => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},

          primary_alias_username_before => $cc.$ac.$sn.$ext,
          primary_alias_username_after => $cc.$ac.$sn.$ext,
          pilot_primary_alias_username_before => $cc.$ac.$sn,
          pilot_primary_alias_username_after => $cc.$ac.$sn,

    ),
    _check_event_history("end_profile when terminating a pbx extension subscriber w alias: ",$subscriber->{id},"%profile",[
        {},{},{},{},{},
        { %subscriber_event,

          type => "update_profile",
          old_status => $subscriberprofile2->{id},
          new_status => $subscriberprofile3->{id},

          non_primary_alias_username => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
        },
        { %subscriber_event,

          type => "update_profile",
          old_status => $subscriberprofile2->{id},
          new_status => $subscriberprofile3->{id},

          non_primary_alias_username => $new_aliases->[1]->{cc}.$new_aliases->[1]->{ac}.$new_aliases->[1]->{sn},
        },
    ]);

    _update_subscriber($pilot_subscriber, status => 'terminated');
    my %pilot_event = (
        subscriber_id => $pilot_subscriber->{id},
          subscriber_profile_id => $subscriberprofile3->{id}, subscriber_profile_name => $subscriberprofile3->{name},
          subscriber_profile_set_id => $subscriberprofile3set->{id}, subscriber_profile_set_name => $subscriberprofile3set->{name},
          primary_number_cc => $cc, primary_number_ac => $ac, primary_number_sn => $sn,
          pilot_subscriber_id => $pilot_subscriber->{id},
          pilot_subscriber_profile_id => $subscriberprofile3->{id}, pilot_subscriber_profile_name => $subscriberprofile3->{name},
          pilot_subscriber_profile_set_id => $subscriberprofile3set->{id}, pilot_subscriber_profile_set_name => $subscriberprofile3set->{name},
          pilot_primary_number_cc => $cc, pilot_primary_number_ac => $ac, pilot_primary_number_sn => $sn,

          #would be this:
          #$new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
          #but since api termination always returns aliases to the pilot:
          #first_non_primary_alias_username_before => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_after => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
          first_non_primary_alias_username_after => undef,
          #pilot_first_non_primary_alias_username_before => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_after => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
          pilot_first_non_primary_alias_username_after => undef,

          primary_alias_username_before => $cc.$ac.$sn,
          primary_alias_username_after => $cc.$ac.$sn,
          pilot_primary_alias_username_before => $cc.$ac.$sn,
          pilot_primary_alias_username_after => $cc.$ac.$sn,

    );
    _check_event_history("end_profile when terminating a pbx pilot subscriber w alias: ",$pilot_subscriber->{id},"%profile",[
        {},{},{},{},{},
        #aliases ordered by id, so by the order they were created:
        #id=2:0002
        #id=6:0003
        #--
        #id=4:0004
        #id=5:0005
        #-->
        #id=2:0002
        #id=4:0004
        #id=5:0005
        #id=6:0003
        { %pilot_event,

          type => "end_profile",
          old_status => $subscriberprofile3->{id},
          new_status => '',

          non_primary_alias_username => $new_pilot_aliases->[0]->{cc}.$new_pilot_aliases->[0]->{ac}.$new_pilot_aliases->[0]->{sn},
        },

                { %pilot_event,

          type => "end_profile",
          old_status => $subscriberprofile3->{id},
          new_status => '',

          non_primary_alias_username => $new_aliases->[0]->{cc}.$new_aliases->[0]->{ac}.$new_aliases->[0]->{sn},
        },


                { %pilot_event,

          type => "end_profile",
          old_status => $subscriberprofile3->{id},
          new_status => '',

          non_primary_alias_username => $new_aliases->[1]->{cc}.$new_aliases->[1]->{ac}.$new_aliases->[1]->{sn},
        },
        { %pilot_event,

          type => "end_profile",
          old_status => $subscriberprofile3->{id},
          new_status => '',

          non_primary_alias_username => $new_pilot_aliases->[1]->{cc}.$new_pilot_aliases->[1]->{ac}.$new_pilot_aliases->[1]->{sn},
        },

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

    foreach my $field (keys %$expected) {
        $ok = is($got->{$field},$expected->{$field},$label . "check event " . $got->{$field} . " $field") && $ok;
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
