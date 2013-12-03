use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ssl/ngcp/api/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ssl/ngcp/api/ca-cert.pem";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/contacts/');
    $res = $ua->request($req);
    ok($res->code == 200, "check options request");
    ok($res->header('Accept-Post') eq "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-contacts", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

# collection test
my $firstcontact = undef;
{
    # create 6 new system contacts (no reseller)
    my %contacts = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/contacts/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            firstname => "Test_First_$i",
            lastname  => "Test_Last_$i",
            email     => "test.$i\@test.invalid",
            reseller_id => 1,
        }));
        $res = $ua->request($req);
        ok($res->code == 201, "create test contact $i");
        $contacts{$res->header('Location')} = 1;
        $firstcontact = $res->header('Location') unless $firstcontact;
    }

    # try to create invalid contact without email
    $req = HTTP::Request->new('POST', $uri.'/api/contacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "Test_First_invalid",
        lastname  => "Test_Last_invalid",
    }));
    $res = $ua->request($req);
    ok($res->code == 422, "create invalid test contact with missing email");
    my $email_err = JSON::from_json($res->decoded_content);
    ok($email_err->{code} eq "422", "check error code in body");
    ok($email_err->{message} =~ /field=\'email\'/, "check error message in body");

    # try to create invalid contact with invalid reseller_id
    $req = HTTP::Request->new('POST', $uri.'/api/contacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "Test_First_invalid",
        lastname  => "Test_Last_invalid",
        email     => "test.invalid\@test.invalid",
        reseller_id => 99999,
    }));
    $res = $ua->request($req);
    ok($res->code == 422, "create test contact with invalid reseller_id");
    my $reseller_err = JSON::from_json($res->decoded_content);
    ok($reseller_err->{code} eq "422", "check error code in body");
    ok($reseller_err->{message} =~ /Invalid reseller_id/, "check error message in body");

    # iterate over contacts collection to check next/prev links
    my $nexturi = $uri.'/api/contacts/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        ok($res->code == 200, "fetch contacts page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        ok($selfuri eq $nexturi, "check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        ok($collection->{total_count} > 0, "check 'total_count' of collection");

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
        ok((ref $collection->{_links}->{'ngcp:contacts'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:contacts'} eq "HASH"), "check if 'ngcp:contacts' is array/hash-ref");

        # remove any contact we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:contacts'} eq "HASH") {
            # TODO: handle hashref
            delete $contacts{$collection->{_links}->{'ngcp:contacts'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:contacts'} }) {
                delete $contacts{$c->{href}};
            }
        }
             
    } while($nexturi);

    ok(keys %contacts == 0, "check if all test contacts have been found");
}

# test contacts item
{
    $req = HTTP::Request->new('GET', $uri.'/'.$firstcontact);
    $res = $ua->request($req);
    ok($res->code == 200, "fetch one contact item");
    my $contact = JSON::from_json($res->decoded_content);
    ok(exists $contact->{firstname}, "check existence of firstname");
    ok(exists $contact->{lastname}, "check existence of lastname");
    ok(exists $contact->{email}, "check existence of email");
    ok(exists $contact->{reseller_id}, "check existence of reseller_id");
    if(defined $contact->{reseller_id}) {
        ok($res->decoded_content =~ /\"reseller_id\"\s*:\s*\d+/, "check if reseller_id is number");
    }
    
    # PUT same result again
    my $old_contact = { %$contact };
    delete $contact->{_links};
    delete $contact->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstcontact);
    
    # check if it fails without If-Match
    $req->header('Content-Type' => 'application/json');
    $res = $ua->request($req);
    ok($res->code == 428, "check put precondition-required");

    $req->header('If-Match' => '*');

    # check if it fails without content type
    $req->remove_header('Content-Type');
    $res = $ua->request($req);
    ok($res->code == 415, "check put missing content type");

    # check if it fails with unsupported content type
    $req->header('Content-Type' => 'application/xxx');
    $res = $ua->request($req);
    ok($res->code == 415, "check put invalid content type");

    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/json');

    # check if it fails with missing Prefer
    $res = $ua->request($req);
    ok($res->code == 400, "check put missing prefer");

    # check if it fails with invalid Prefer
    $req->header('Prefer' => "return=invalid");
    $res = $ua->request($req);
    ok($res->code == 400, "check put invalid prefer");


    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=representation");

    # check if it fails with missing body
    $res = $ua->request($req);
    ok($res->code == 400, "check put no body");

    # check if put is ok
    $req->content(JSON::to_json($contact));
    $res = $ua->request($req);
    ok($res->code == 200, "check put successful");

    my $new_contact = JSON::from_json($res->decoded_content);
    is_deeply($old_contact, $new_contact, "check put if unmodified put returns the same");

    # check if a contact without reseller doesn't have a resellers link
    $contact->{reseller_id} = undef;
    $req->content(JSON::to_json($contact));
    $res = $ua->request($req);
    ok($res->code == 200, "check put successful");
    $new_contact = JSON::from_json($res->decoded_content);
    ok(!defined $new_contact->{reseller_id}, "check put if reseller_id is undef");
    ok(!exists $new_contact->{_links}->{'ngcp:resellers'}, "check put absence of ngcp:resellers relation");

    # check if a contact with reseller has resellers link
    $contact->{reseller_id} = 1;
    $req->content(JSON::to_json($contact));
    $res = $ua->request($req);
    ok($res->code == 200, "check put successful");
    $new_contact = JSON::from_json($res->decoded_content);
    ok(defined $new_contact->{reseller_id} && $new_contact->{reseller_id} == 1, "check put if reseller_id is set");
    ok(exists $new_contact->{_links}->{'ngcp:resellers'} && ref $new_contact->{_links}->{'ngcp:resellers'} eq "HASH", "check put presence of ngcp:resellers relation");
    ok($new_contact->{_links}->{'ngcp:resellers'}->{href} eq "/api/resellers/1", "check put correct ngcp:resellers relation href");


}

done_testing;

# vim: set tabstop=4 expandtab:
