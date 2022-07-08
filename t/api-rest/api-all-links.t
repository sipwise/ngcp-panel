use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);
my $ngcp_type = $ENV{NGCP_TYPE} || "sppro";

my ($ua, $req, $res);

#to eliminate 'Too many header lines (limit is 128) at /usr/share/perl5/Net/HTTP/Methods.pm line 383. 
#on the curl -i -k --user administrator:administrator -X OPTIONS -H 'Content-Type: application/json' 'https://127.0.0.1:1443/api/?foo=bar&bla' 
use LWP::Protocol::http; 
push @LWP::Protocol::http::EXTRA_SOCK_OPTS, MaxHeaderLines => 256;


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

    my @links = $res->header('Link');
    my $rex = qr!^</api/[a-z]+/>; rel="collection http://purl\.org/sipwise/ngcp-api/#rel-([a-z]+s|topupcash|managersecretary)"$!;
    foreach my $link(@links) {
        (my ($relname)) = ($link =~ $rex);
        # skip interceptions since there is no longer an LI admin by default
        next if $relname eq "interceptions";
        my $skip = 0;
        if ($ngcp_type ne "sppro" && $ngcp_type ne "carrier") {
            foreach my $pro_only (qw(phonebookentries headerrulesets headerrules headerruleconditions headerruleactions)) {
                if ($relname eq $pro_only) {
                    ok(1, "skip '$pro_only' links check as it is a PRO only endpoint");
                    $skip = 1;
                }
            }
        }
        next if $skip;
        # now get this rel
        $req = HTTP::Request->new('OPTIONS', "$uri/api/$relname/");
        $res = $ua->request($req);
        is($res->code, 200, "check options request to $relname");

        my $opts = JSON::from_json($res->decoded_content);
        ok(exists $opts->{methods}, "OPTIONS should return methods");
        is(ref $opts->{methods}, "ARRAY", "OPTIONS methods should be array");
        if (grep {$_ eq "GET"} @{ $opts->{methods} }) {
            # skip calllists collection, as it needs a subscriber_id parameter also in the collection
            next if $relname eq "calllists";
            next if $relname eq "resellerbrandinglogos";
            next if $relname eq "conversations";
            next if $relname eq "phonebookentries";
            #my $uri = "$uri/api/$relname/";
            #if('conversations' eq $relname){
            #    $uri .= '?type=call';
            #}elsif('calllist' eq $relname){
            #    $uri .= '?type=call';
            #}elsif('calllist' eq $relname){
            #    $uri .= '?reseller_id=1';
            #}
            $req = HTTP::Request->new('GET', "$uri/api/$relname/");
            $res = $ua->request($req);
            is($res->code, 200, "check GET request to $relname collection")
                || diag($res->status_line);
        }
    }
}

done_testing;

# vim: set tabstop=4 expandtab:
