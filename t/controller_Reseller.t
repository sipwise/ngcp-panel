use strict;
use warnings;
use Test::More;
use JSON::Parse 'valid_json';
use JSON qw( from_json );
use Data::Dumper;


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
$admin->follow_link_ok( {text => 'Admin'}, "Go to admin Login");

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
$admin->content_contains('"sEcho":"1337"');

my $returndata = from_json($admin->content());
if($returndata->{aaData}->[0]->[1] eq "reseller 1") { #using mock data

    ok($returndata->{aaData}->[0]->[0] == 1, "check id field");
    ok($returndata->{aaData}->[0]->[2] == 1, "check contract.id field");
    ok($returndata->{aaData}->[0]->[3] eq "active", "check status field");
    ok($returndata->{iTotalRecords} == 6, "iTotalRecords (all mock data) should be 6");
    ok($returndata->{iTotalDisplayRecords} == 4, "iTotalDisplayRecords (filtered mock data) should be 4");
    ok($returndata->{sEcho} eq "1337");
}
####

done_testing();
