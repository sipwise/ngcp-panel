use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'rewriterules',
    embedded_resources => [qw/rewriterulesets/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    rewriterules => {
        data => {
            set_id  =>  sub { return shift->get_id('rewriterulesets',@_); },
            #match_pattern   => '^111$',
            match_pattern   => '^111$',
            replace_pattern => '222',
            description     => 'test_api rewrite rule',
            direction       => 'in',#out
            field           => 'caller',#calee
            priority        => '1',
            enabled         => '1',
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('rewriterules'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
my $rules = $test_machine->check_create_correct( 3, sub{ 
    $_[0]->{description} .=  $_[1]->{i};
    #to test inflate/deflate
    $_[0]->{match_pattern} =  '${caller_in}_' . time().$_[1]->{i}; 
    $_[0]->{replace_pattern} =  '${caller_in}_' . time().$_[1]->{i}; 
} );
$test_machine->check_get2put();
$test_machine->check_bundle();
{
    $rules->[1]->{content}->{match_pattern} = '${callee_in}_' . time();
    $rules->[1]->{content}->{replace_pattern} = '${callee_in}_' . time();
    $test_machine->request_put(@{$rules->[1]}{qw/content location/});
    my ($res, $rule, $req) = $test_machine->check_item_get($rules->[1]->{location});
    #While I don't know how to test raw data when we receive inflated
    #so just checked in the DB    
    #print Dumper $rules->[1]->{content};
    ok(exists $rule->{direction} && $rule->{direction} =~ /^(in|out)$/ , "check existence of direction");
    ok(exists $rule->{field} && $rule->{field} =~ /^(caller|callee)$/, "check existence of field");
    ok(exists $rule->{match_pattern} && length($rule->{match_pattern}) > 0, "check existence of match_pattern");
    ok(exists $rule->{replace_pattern} && length($rule->{replace_pattern}) > 0, "check existence of replace_pattern");
    ok(exists $rule->{description} && length($rule->{description}) > 0, "check existence of description");
    ok(exists $rules->[1]->{content}->{_links}->{'ngcp:rewriterules'}, "check put presence of ngcp:rewriterules relation");
    ok(exists $rules->[1]->{content}->{_links}->{'ngcp:rewriterulesets'}, "check put presence of ngcp:rewriterulesets relation");
}
# try to create rule with invalid set_id
{
    my ($res, $err) = $test_machine->check_item_post(sub{$_[0]->{set_id} = 999999;});
    is($res->code, 422, "create rule with invalid set_id");
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Invalid 'set_id'/, "check error message in body");
}
# try to create rule with negative set_id
{
    my ($res, $err) = $test_machine->check_item_post(sub{$_[0]->{set_id} = -100;});
    is($res->code, 422, "create rule with negative set_id");
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/(Invalid|Validation failed).*'set_id'/, "check error message in body");
}
# try to create rule without set_id
{
    my ($res, $err) = $test_machine->check_item_post(sub{ delete $_[0]->{set_id};});
    is($res->code, 422, "create rule without set_id");
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Required: 'set_id'|set_id.*required/, "check error message in body");
}
# try to create rule with missing match_pattern
{
    my ($res, $err) = $test_machine->check_item_post(sub{ delete $_[0]->{match_pattern};});
    is($res->code, 422, "create rule with missing match_pattern");
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/field='match_pattern'/, "check error message in body");
}
# try to create rule with invalid direction and field
{
    my ($res, $err) = $test_machine->check_item_post(sub{
        $_[0]->{direction} = 'foo';
        $_[0]->{field} = 'bar';
    });
    is($res->code, 422, "create rule with invalid direction and field");
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/field='direction'/, "check error message in body");
    like($err->{message}, qr/field='field'/, "check error message in body");
}

$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
