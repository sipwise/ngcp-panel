use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

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

    my @links = $res->header('Link');
    my $rex = qr!^</api/[a-z]+/>; rel="collection http://purl\.org/sipwise/ngcp-api/#rel-([a-z]+s|topupcash|managersecretary)"$!;
    foreach my $link(@links) {
        (my ($relname)) = ($link =~ $rex);
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
