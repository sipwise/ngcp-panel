#use Sipwise::Base;
use strict;

#use Moose;
use Sipwise::Base;
use Test::Collection;
use Test::FakeData;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;


#init test_machine
my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'billingfees' => {
        data => {
            billing_profile_id      => sub { return shift->get_id('billingprofiles', @_); },
            billing_zone_id         => sub { return shift->get_id('billingzones', @_); },
            destination             => "^1234",
            direction               => "out",
            onpeak_init_rate        => 1,
            onpeak_init_interval    => 60,
            onpeak_follow_rate      => 1,
            onpeak_follow_interval  => 30,
            offpeak_init_rate       => 0.5,
            offpeak_init_interval   => 60,
            offpeak_follow_rate     => 0.5,
            offpeak_follow_interval => 30,
        },
        'query' => ['billing_zone_id'],
    },
});
my $test_machine = Test::Collection->new(
    name => 'billingfees',
    embedded => [qw/billingzones billingprofiles/]
);
$test_machine->DATA_ITEM_STORE($fake_data->process('billingfees'));
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
$test_machine->form_data_item( );
# create 3 new field billing fees from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{destination} .= $_[1]->{i} ; } );
$test_machine->check_bundle();

# specific tests

# try to create fee without billing_profile_id
{
    my ($res, $err) = $test_machine->request_post(sub{delete $_[0]->{billing_profile_id};});
    is($res->code, 422, "create billing zone without billing_profile_id");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Missing parameter 'billing_profile_id'/, "check error message in body");
}
# try to create fee with invalid billing_profile_id
{
    my ($res, $err) = $test_machine->request_post(sub{$_[0]->{billing_profile_id} = 99999;});
    is($res->code, 422, "create billing zone with invalid billing_profile_id");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_profile_id'/, "check error message in body");
}
# try to create fee without billing_zone_id
{
    my ($res, $err) = $test_machine->request_post(sub{delete $_[0]->{billing_zone_id};});
    is($res->code, 422, "create billing zone without billing_zone_id");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_zone_id'/, "check error message in body");
}
# try to create fee with invalid billing_zone_id
{
    my ($res, $err) = $test_machine->request_post(sub{$_[0]->{billing_zone_id} = 99999;});
    is($res->code, 422, "create billing zone with invalid billing_zone_id");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_zone_id'/, "check error message in body");
}
# try to create fee with implicit zone which already exists
{
    my $t = time;
    my ($res, $err) = $test_machine->request_post(sub{
        delete $_[0]->{billing_zone_id};
        $_[0]->{billing_zone_zone} = 'apitestzone';
        $_[0]->{billing_zone_detail} = 'api_test zone';
        $_[0]->{destination} = "^".$t;
    });
    is($res->code, 201, "create profile fee with existing implicit zone");
    my($z_fee,$req);
    ($res, $z_fee, $req) = $test_machine->request_get($test_machine->base_uri.$res->header('Location'));
    is($res->code, 200, "fetch profile fee with existing implicit zone");
    ok(exists $z_fee->{billing_zone_id} && $z_fee->{billing_zone_id} == $test_machine->DATA_ITEM->{billing_zone_id}, "check if implicit zone returns the correct zone id");
}
# try to create fee with implicit zone which doesn't exist yet
{
    my $t = time;
    my ($res, $err) = $test_machine->request_post(sub{
        delete $_[0]->{billing_zone_id};
        $_[0]->{billing_zone_zone} = 'apitestzone'.$t;
        $_[0]->{billing_zone_detail} = 'api_test zone'.$t;
        $_[0]->{destination} = "^".$t;
    });
    is($res->code, 201, "create profile fee with new implicit zone");
    my($z_fee, $req, $content);
    ($res, $z_fee, $req) = $test_machine->request_get($test_machine->base_uri.$res->header('Location'));
    is($res->code, 200, "fetch profile fee with new implicit zone");
    ok(exists $z_fee->{billing_zone_id} && $z_fee->{billing_zone_id} > $test_machine->DATA_ITEM->{billing_zone_id}, "check if implicit zone returns a new zone id");

    ($req,$res,$content) = $test_machine->request_delete($test_machine->base_uri.$z_fee->{_links}->{'ngcp:billingzones'}->{href});
    is($res->code, 204, "delete new implicit zone");

    ($res) = $test_machine->request_get($test_machine->base_uri.$z_fee->{_links}->{'self'}->{href});
    is($res->code, 404, "check if fee is deleted when zone is deleted");    
}

{
    my (undef, $item_first_get) = $test_machine->check_item_get;
    ok(exists $item_first_get->{billing_profile_id} && $item_first_get->{billing_profile_id} == $test_machine->DATA_ITEM->{billing_profile_id}, "check existence of billing_profile_id");
    ok(exists $item_first_get->{billing_zone_id}    && $item_first_get->{billing_zone_id} == $test_machine->DATA_ITEM->{billing_zone_id}, "check existence of billing_zone_id");
    ok(exists $item_first_get->{direction}          && $item_first_get->{direction} =~ /^(in|out)$/ , "check existence of direction");
    ok(exists $item_first_get->{source}             && length($item_first_get->{source}) > 0, "check existence of source");
    ok(exists $item_first_get->{destination}        && length($item_first_get->{destination}) > 0, "check existence of destination");
}
{
    my($res,$item_put,$req) = $test_machine->check_get2put();
    $test_machine->check_embedded($item_put);
}
{
    my $t = time;
    my($res,$mod_fee) = $test_machine->check_patch_correct( [ { op => 'replace', path => '/direction', value => 'in' } ] );
    is($mod_fee->{direction}, "in", "check patched replace op");
}
{
    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/billing_profile_id', value => undef } ] );
    is($res->code, 422, "check patched undef billing_profile_id");
}
{
    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/billing_profile_id', value => 99999 } ] );
    is($res->code, 422, "check patched invalid billing_profile_id");
}
{
    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/billing_zone_id', value => undef } ] );
    is($res->code, 422, "check patched undef billing_zone_id");
}
{
    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/billing_zone_id', value => 99999 } ] );
    is($res->code, 422, "check patched invalid billing_zone_id");
}

$test_machine->clear_test_data_all();

{
    my $uri = $test_machine->base_uri.'/api/billingzones/'.$test_machine->DATA_ITEM->{billing_zone_id};
    my($req,$res,$content) = $test_machine->request_delete($uri);
    is($res->code, 204, "check delete of zone");
    ($res, $content, $req) = $test_machine->request_get($uri);
    is($res->code, 404, "check if deleted zone is really gone");
}
$test_machine = undef;
$fake_data = undef;
done_testing;
















# vim: set tabstop=4 expandtab:
