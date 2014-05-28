use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

# OPTIONS tests
{
    diag("server is $uri");
    # test some uri params
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/?foo=bar&bla');
    $res = $ua->request($req);
    is($res->code, 200, "check options request with uri params");

    $req = HTTP::Request->new('OPTIONS', $uri.'/api/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( PUT POST DELETE )) {
        ok(!grep(/^$opt$/, @hopts), "check for non-existence of '$opt' in Allow header");
        ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for non-existence of '$opt' in body");
    }

    my @links = $res->header('Link');
    my $rels = { contracts => 1,
                 subscriberpreferences => 1,
                 subscriberpreferencedefs => 1,
                 domainpreferencedefs => 1,
                 billingzones => 1,
                 systemcontacts => 1,
                 domains => 1,
                 billingfees => 1,
                 rewriterules => 1,
                 resellers => 1,
                 rewriterules => 1,
                 resellers => 1,
                 rewriterulesets => 1,
                 customercontacts => 1,
                 billingprofiles => 1,
                 customers => 1,
                 domainpreferences => 1,
                 subscribers => 1,
                 callforwards => 1,
                 cfdestinationsets => 1,
                 cftimesets => 1,
                 cfmappings => 1,
                 pbxdevices => 1,
                 pbxdeviceprofiles => 1,
                 pbxdeviceconfigs => 1,
                 pbxdevicemodels => 1,
                 speeddials => 1,
                 emailtemplates => 1,
                 subscriberprofiles => 1,
                 subscriberprofilesets => 1,
                 voicemails => 1,
                 voicemailrecordings => 1,
                 soundsets => 1,
                 soundfiles => 1,
                 soundfilerecordings => 1,
                 reminders => 1,
                 trustedsources => 1,
                 voicemailsettings => 1,
                 subscriberregistrations => 1,
                 calls => 1,
                 customerzonecosts => 1,
                 autoattendants => 1,
                 faxserversettings => 1,
                  };
    foreach my $link(@links) {
        my $rex = qr!^</api/[a-z]+/>; rel="collection http://purl\.org/sipwise/ngcp-api/#rel-([a-z]+s)"$!;
        like($link, $rex, "check for valid link syntax");
        my ($relname) = ($link =~ $rex);
        ok(exists $rels->{$relname}, "check for '$relname' collection in Link");
        delete $rels->{$relname};
    }
    is(scalar (keys %{ $rels }), 0, "check if all collections are present in Link");
}

done_testing;

# vim: set tabstop=4 expandtab:
