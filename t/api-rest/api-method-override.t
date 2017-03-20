use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $is_local_env = 0;

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
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch test billing profile");
my $billing_profile = JSON::from_json($res->decoded_content);

# first, create a contact
$req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    firstname => "cust_contact_first",
    lastname  => "cust_contact_last",
    email     => "cust_contact\@custcontact.invalid",
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create customer contact");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch customer contact");
my $custcontact = JSON::from_json($res->decoded_content);

{

    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        billing_profile_id => $billing_profile->{id},
        max_subscribers => undef,
        external_id => undef,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test customer");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test customer");
    my $customer = JSON::from_json($res->decoded_content);

    #curl -X DELETE -H 'Connection: close' -H 'Content-Type: application/json-patch+json' -H 'X-HTTP-Method-Override: PATCH' 'https://127.0.0.1:1443/api/customers/3' -k -u administrator:administrator --data-binary '[{ "op" : "replace", "path" : "/status", "value" : "terminated" }]'

    $req = HTTP::Request->new('DELETE', $uri.'/api/customers/'.$customer->{id});
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('x-tunneled-method' => 'PATCH');

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "patch customer test customer with DELETE");
    my $mod_customer = JSON::from_json($res->decoded_content);

    is($mod_customer->{status}, 'terminated','test customer successfully terminated');

}

done_testing;
