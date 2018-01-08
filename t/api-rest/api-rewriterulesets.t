use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'rewriterulesets',
    embedded_resources => []
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    rewriterulesets => {
        'data' => {
            reseller_id     => sub { return shift->get_id('resellers',@_); },
            name            => 'api_test',
            description     => 'api_test rule set description',
            caller_in_dpid  => '1',
            callee_in_dpid  => '2',
            caller_out_dpid => '3',
            callee_out_dpid => '4',
            rewriterules    => [{
                    match_pattern   => '${caller_in}_${callee_in}_' . time().'1',
                    replace_pattern => '2221',
                    description     => 'test_api rewrite rule 1',
                    direction       => 'in',#out
                    field           => 'caller',#calee
                    priority        => '2',
                    enabled         => '1',
                },{
                    match_pattern   => '${caller_in}_${callee_in}_' . time().'2',
                    replace_pattern => '2222',
                    description     => 'test_api rewrite rule 2',
                    direction       => 'in',#out
                    field           => 'caller',#calee
                    priority        => '3',
                    enabled         => '1',
                },{
                    match_pattern   => '${caller_in}_${callee_in}_' . time().'3',
                    replace_pattern => '2223',
                    description     => 'test_api rewrite rule 3',
                    direction       => 'in',#out
                    field           => 'caller',#calee
                    priority        => '1',
                    enabled         => '1',
                },
            ],
        },
        'query' => ['name'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('rewriterulesets'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
my $sets = $test_machine->check_create_correct( 3, sub{ $_[0]->{name} .=  $_[1]->{i}.time(); } );
$test_machine->check_get2put();
$test_machine->check_bundle();
#print Dumper $sets;
for(my $i=0; $i < scalar @$sets; $i++){
    my $set = $sets->[$i];
    my $rewriterules = $sets->[$i]->{content}->{rewriterules};
    my $priority = -1;
    for(my $j=0; $j < scalar @{$rewriterules}; $j++){
        my $priority_new = $rewriterules->[$j]->{priority};
        diag("Check priority order $i:$j: $priority < $priority_new");
        ok($priority < $priority_new) ;
        $priority = $priority_new;
    }
}

# try to create ruleset without reseller_id
{
    my ($res, $err) = $test_machine->check_item_post(sub{delete $_[0]->{reseller_id};});
    is($res->code, 422, "create ruleset without reseller_id");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
}


$test_machine->clear_test_data_all();

done_testing;

__DATA__

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstrule);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/description', value => 'iwasmodifiedbyreplace' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched rule item");
    my $mod_rule = JSON::from_json($res->decoded_content);
    is($mod_rule->{description}, "iwasmodifiedbyreplace", "check patched replace op");
    is($mod_rule->{_links}->{self}->{href}, $firstrule, "check patched self link");
    is($mod_rule->{_links}->{collection}->{href}, '/api/rewriterules/', "check patched collection link");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/description', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef description");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/direction', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid direction");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/match_pattern', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef match_pattern");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/field', value => 'foobar' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid field");
}

# vim: set tabstop=4 expandtab:
