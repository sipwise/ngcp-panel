use strict;
use warnings;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

#goto SKIP;
# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/systemcontacts/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-systemcontacts", "check Accept-Post header in options response");
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
my @allcontacts = ();
{
    # create 6 new system contacts (no reseller)
    my %contacts = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            firstname => "Test_First_$i",
            lastname  => "Test_Last_$i",
            email     => "test.$i\@test.invalid",
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test contact $i");
        $contacts{$res->header('Location')} = 1;
        push @allcontacts, $res->header('Location');
        $firstcontact = $res->header('Location') unless $firstcontact;
    }

    # try to create invalid contact without email
    $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "Test_First_invalid",
        lastname  => "Test_Last_invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create invalid test contact with missing email");
    my $email_err = JSON::from_json($res->decoded_content);
    is($email_err->{code}, "422", "check error code in body");
    ok($email_err->{message} =~ /field=\'email\'/, "check error message in body");

    # iterate over contacts collection to check next/prev links
    my $nexturi = $uri.'/api/systemcontacts/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch contacts page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        is($selfuri, $nexturi, "check _links.self.href of collection");
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
        ok((ref $collection->{_links}->{'ngcp:systemcontacts'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:systemcontacts'} eq "HASH"), "check if 'ngcp:contacts' is array/hash-ref");

        # remove any contact we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:systemcontacts'} eq "HASH") {
            # TODO: handle hashref
            delete $contacts{$collection->{_links}->{'ngcp:systemcontacts'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:systemcontacts'} }) {
                delete $contacts{$c->{href}};
            }
        }

    } while($nexturi);

    is(scalar(keys %contacts), 0, "check if all test contacts have been found");
}

# test contacts item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstcontact);
    $res = $ua->request($req);
    is($res->code, 200, "check options on item");
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    my $opts = JSON::from_json($res->decoded_content);
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS PUT PATCH DELETE )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    my $opt = 'POST';
    ok(!grep(/^$opt$/, @hopts), "check for absence of '$opt' in Allow header");
    ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for absence of '$opt' in body");

    $req = HTTP::Request->new('GET', $uri.'/'.$firstcontact);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one contact item");
    my $contact = JSON::from_json($res->decoded_content);
    ok(exists $contact->{firstname}, "check existence of firstname");
    ok(exists $contact->{lastname}, "check existence of lastname");
    ok(exists $contact->{email}, "check existence of email");
    ok(exists $contact->{id}, "check existence of id");
    like($contact->{id}, qr/[0-9]+/, "check validity of id");
    ok(!exists $contact->{reseller_id}, "check absence of reseller_id");

    # PUT same result again
    my $old_contact = { %$contact };
    delete $contact->{_links};
    delete $contact->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstcontact);
    $req->header('Prefer' => 'return=minimal');

    # check if it fails without content type
    $req->remove_header('Content-Type');
    $res = $ua->request($req);
    is($res->code, 415, "check put missing content type");

    # check if it fails with unsupported content type
    $req->header('Content-Type' => 'application/xxx');
    $res = $ua->request($req);
    is($res->code, 415, "check put invalid content type");

    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/json');

    # check if it fails with invalid Prefer
    $req->header('Prefer' => "return=invalid");
    $res = $ua->request($req);
    is($res->code, 400, "check put invalid prefer");

    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=representation");

    # check if it fails with missing body
    $res = $ua->request($req);
    is($res->code, 400, "check put no body");

    # check if put is ok
    $req->content(JSON::to_json($contact));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_contact = JSON::from_json($res->decoded_content);
    is_deeply($old_contact, $new_contact, "check put if unmodified put returns the same");

    # check if a system contact with reseller has no resellers link
    $contact->{reseller_id} = 1;
    $req->content(JSON::to_json($contact));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");
    $new_contact = JSON::from_json($res->decoded_content);
    ok(!exists $new_contact->{reseller_id}, "check put if reseller_id is absent");
    ok(!exists $new_contact->{_links}->{'ngcp:resellers'}, "check put absence of ngcp:resellers relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstcontact);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/firstname', value => 'patchedfirst' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched contact item");
    my $mod_contact = JSON::from_json($res->decoded_content);
    is($mod_contact->{firstname}, "patchedfirst", "check patched replace op");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/firstname', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched contact item");
    $mod_contact = JSON::from_json($res->decoded_content);
    ok(exists $mod_contact->{firstname} && !defined $mod_contact->{firstname}, "check patched replace op for undef");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/email', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched contact with unset email");
}

# DELETE
{ #regular delete:
    foreach my $contact(@allcontacts) {
        $req = HTTP::Request->new('DELETE', $uri.'/'.$contact);
        $res = $ua->request($req);
        is($res->code, 204, "check delete of contact");
    }
}

#SKIP:
#MT#20639
my $t = time;
my $reseller_id = 1;

$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    domain => 'test' . $t . '.example.org',
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test domain");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test domain");
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

my %subscriber_map = ();
my %contract_map = ();
my %system_contact_map = ();

{ #termination, if a terminated contract exists:

    my $system_contact = _create_system_contact();
    my $contract = _create_contract($system_contact->{id});
    _delete_system_contact($system_contact,423);
    _update_contract($contract,status => "terminated");
    _delete_system_contact($system_contact);

}

sub _create_system_contact {

    my (@further_opts) = @_;

    $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "syst_contact_first",
        lastname  => "syst_contact_last",
        email     => "syst_contact\@systcontact.invalid",
        #reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test system contact");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test system contact");
    my $system_contact = JSON::from_json($res->decoded_content);
    $system_contact_map{$system_contact->{id}} = $system_contact;
    return $system_contact;

}

sub _delete_system_contact {

    my ($contact,$expected_code) = @_;
    $expected_code //= 204;
    my $url = $uri.'/api/systemcontacts/'.$contact->{id};
    $req = HTTP::Request->new('DELETE', $url);
    $res = $ua->request($req);
    if ($expected_code eq '204') {
        is($res->code, 204, "delete test system contact");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 404, "test system contact is not found");
        return delete $system_contact_map{$contact->{id}};
    } else {
        is($res->code, $expected_code, "delete test system contact returns $expected_code");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 200, "test system contact is still found");
        return undef;
    }

}

sub _create_contract {

    my ($contact_id,@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $contact_id,
        type => "sippeering",
        billing_profile_id => $billing_profile_id,
        max_subscribers => undef,
        external_id => undef,
        #status => "active",
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test contract");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test contract");
    my $contract = JSON::from_json($res->decoded_content);
    $contract_map{$contract->{id}} = $contract;
    return $contract;

}

sub _update_contract {

    my ($contract,@further_opts) = @_;
    $req = HTTP::Request->new('PUT', $uri.'/api/contracts/'.$contract->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        %$contract,
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "patch test contract");
    $contract = JSON::from_json($res->decoded_content);
    $contract_map{$contract->{id}} = $contract;
    return $contract;

}

done_testing;

# vim: set tabstop=4 expandtab:
