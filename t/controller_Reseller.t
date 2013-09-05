use strict;
use warnings;
use Test::More skip_all => 'Not yet working, the Mechanize does not consider our blib setting';
use JSON::Parse 'valid_json';
use JSON qw( from_json );
use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Reseller;

my $response = request('/reseller');
ok( $response->is_success || $response->is_redirect , 'Request should succeed' );

#Testing /ajax
BEGIN { use_ok("Test::WWW::Mechanize::Catalyst" => "NGCP::Panel") }

my $admin = Test::WWW::Mechanize::Catalyst->new;
$admin->get_ok("http://localhost/reseller", "Check redirect");
#not yet tested: /reseller/ajax should give 403
$admin->content_contains("Sign In", "Should be on login page");

$admin->submit_form(
    fields => {
        username => 'administrator',
        password => 'administrator',
    });

$admin->get_ok("http://localhost/reseller/ajax", "Should get ajax now");
$admin->content_contains('"aaData"');
$admin->content_contains('"iTotalDisplayRecords"');
$admin->content_contains('"iTotalRecords"');
$admin->content_contains('"sEcho"');
ok(valid_json($admin->content()), "Should be valid JSON"); #need JSON::Parse
$admin->get_ok("http://localhost/reseller/ajax?sEcho=1337&sSearch=a&iDisplayStart=0&iDisplayLength=2&iSortCol_0=0&sSortDir_0=asc", "Should get ajax now");
$admin->content_contains('"sEcho":1337');

my $returndata = from_json($admin->content());
if($returndata->{iTotalDisplayRecords} > 0) { #data available

    ok(exists $returndata->{aaData}->[0]->{contract_id}, "contract_id there");
    ok(exists $returndata->{aaData}->[0]->{status}, "status there");
    ok(exists $returndata->{aaData}->[0]->{name}, "name there");
    ok(exists $returndata->{aaData}->[0]->{id}, "id there");
    ok($returndata->{iTotalRecords} >= $returndata->{iTotalDisplayRecords},
        "iTotalRecords >= iTotalDisplayRecords");
}
is($returndata->{sEcho}, "1337", "sEcho is echoed back correctly");
####

done_testing();
