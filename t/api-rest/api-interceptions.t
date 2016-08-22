use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'interceptions',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'interceptions' => {
        'data' => {
            liid        => '1',
            number      => sub { my $self = shift; $self->get_id('subscribers',@_);my $subscriber = $self->get_existent_item('subscribers');return join('',@{$subscriber->{content}->{primary_number}}{qw/cc ac sn/}) },
            x2_host     => '127.0.0.1',
            x2_password => '',
            x2_port     => '1443',
            x2_user     => '',
            x3_host     => '127.0.0.1',
            x3_port     => '2',#todo: empty makes 500, should be fixed
            x3_required => 1,
        },
        'query' => ['liid'],
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('interceptions'));
$test_machine->form_data_item();
my $li = $test_machine->check_create_correct( 1 );
$test_machine->check_get2put();
$test_machine->check_bundle();

{
#18561
    diag("18561: Forbid to change liid;\n\n");
    my $li_18561 = $test_machine->check_create_correct(1)->[0];
    my($res,$content,$request) = $test_machine->request_put(@{$li_18561}{qw/content location/});
    $test_machine->http_code_msg(200, "Check that PUT with the same liid is OK", $res, $content);
    $li_18561->{content}->{liid} .= '1';
    ($res,$content,$request) = $test_machine->request_put(@{$li_18561}{qw/content location/});
    $test_machine->http_code_msg(422, "Check that PUT with different liid is forbidden", $res, $content);
    ok($content->{message} =~ /liid can not be changed/, "check error message in body");
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
}
{
#test empty x3_port
    diag("Empty x3_port;\n\n");
    $test_machine->check_create_correct(1,sub{
        $_[0]->{x3_required} = 0;
        delete $_[0]->{x3_port};
        $_[0]->{x3_host} = '';
    });
}

$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
undef $fake_data;
undef $test_machine;
done_testing;


# vim: set tabstop=4 expandtab:
