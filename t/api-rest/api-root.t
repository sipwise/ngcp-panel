use strict;
use warnings;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

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
        ok(grep { /^$opt$/ } @hopts, "check for existence of '$opt' in Allow header");
        ok(grep { /^$opt$/ } @{ $opts->{methods} }, "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( PUT POST DELETE )) {
        ok(!grep { /^$opt$/ } @hopts, "check for non-existence of '$opt' in Allow header");
        ok(!grep { /^$opt$/ } @{ $opts->{methods} }, "check for non-existence of '$opt' in body");
    }

    my @links = $res->header('Link');
    my $rels = {
        admincerts => 1,
        admins => 1,
        applyrewrites => 1,
        autoattendants => 1,
        balanceintervals => 1,
        bannedips => 1,
        bannedusers => 1,
        billingfees => 1,
        billingnetworks => 1,
        billingprofiles => 1,
        billingzones => 1,
        callcontrols => 1,
        callforwards => 1,
        calllists => 1,
        callqueues => 1,
        callrecordingfiles => 1,
        callrecordings => 1,
        callrecordingstreams => 1,
        calls => 1,
        capabilities => 1,
        ccmapentries => 1,
        cfbnumbersets => 1,
        cfdestinationsets => 1,
        cfmappings => 1,
        cfsourcesets => 1,
        cftimesets => 1,
        contracts => 1,
        conversations => 1,
        customerbalances => 1,
        customercontacts => 1,
        customerfraudevents => 1,
        customerfraudpreferences => 1,
        customerlocations => 1,
        customerpreferencedefs => 1,
        customerpreferences => 1,
        customers => 1,
        customerzonecosts => 1,
        domainpreferencedefs => 1,
        domainpreferences => 1,
        domains => 1,
        emailtemplates => 1,
        emergencymappingcontainers => 1,
        emergencymappings => 1,
        events => 1,
        faxes => 1,
        faxrecordings => 1,
        faxserversettings => 1,
        interceptions => 1,
        invoices => 1,
        invoicetemplates => 1,
        lnpcarriers => 1,
        lnpnumbers => 1,
        mailtofaxsettings => 1,
        maliciouscalls => 1,
        managersecretary => 1,
        metaconfigdefs => 1,
        ncoslevels => 1,
        ncoslnpcarriers => 1,
        ncospatterns => 1,
        numbers => 1,
        partycallcontrols => 1,
        pbxdeviceconfigfiles => 1,
        pbxdeviceconfigs => 1,
        pbxdevicefirmwarebinaries => 1,
        pbxdevicefirmwares => 1,
        pbxdevicemodelimages => 1,
        pbxdevicemodels => 1,
        pbxdevicepreferencedefs => 1,
        pbxdevicepreferences => 1,
        pbxdeviceprofilepreferencedefs => 1,
        pbxdeviceprofilepreferences => 1,
        pbxdeviceprofiles => 1,
        pbxfielddevicepreferencedefs => 1,
        pbxfielddevicepreferences => 1,
        pbxdevices => 1,
        peeringgroups => 1,
        peeringrules => 1,
        peeringinboundrules => 1,
        peeringserverpreferencedefs => 1,
        peeringserverpreferences => 1,
        peeringservers => 1,
        phonebookentries => 1,
        preferencesmetaentries => 1,
        profilepackages => 1,
        profilepreferencedefs => 1,
        profilepreferences => 1,
        reminders => 1,
        resellers => 1,
        rewriterules => 1,
        rewriterulesets => 1,
        rtcapps => 1,
        rtcnetworks => 1,
        rtcsessions => 1,
        sipcaptures => 1,
        sms => 1,
        soundfilerecordings => 1,
        soundfiles => 1,
        soundgroups => 1,
        soundhandles => 1,
        soundsets => 1,
        speeddials => 1,
        subscriberpreferencedefs => 1,
        subscriberpreferences => 1,
        subscriberprofiles => 1,
        subscriberprofilesets => 1,
        subscriberregistrations => 1,
        subscribers => 1,
        systemcontacts => 1,
        #timesets => 1,
        topupcash => 1,
        topuplogs => 1,
        topupvouchers => 1,
        trustedsources => 1,
        upnrewritesets => 1,
        voicemailrecordings => 1,
        voicemailgreetings => 1,
        voicemails => 1,
        voicemailsettings => 1,
        vouchers => 1,
    };
    foreach my $link(@links) {
        my $rex = qr!^</api/[a-z]+/>; rel="collection http://purl\.org/sipwise/ngcp-api/#rel-([a-z]+s|topupcash|managersecretary)"$!;
        like($link, $rex, "check for valid link syntax");
        my ($relname) = ($link =~ $rex);
        ok(exists $rels->{$relname}, "check for '$relname' collection in Link");
        delete $rels->{$relname};
    }
    is(scalar (keys %{ $rels }), 0, "check if all collections are present in Link");
}

done_testing;

# vim: set tabstop=4 expandtab:
