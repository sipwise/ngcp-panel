use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'numbers',
);
my $fake_data = Test::FakeData->new;

$fake_data->set_data_from_script({
    'numbers' => {
        'data' => {
            subscriber_id  => sub { return shift->get_id('subscribers',@_); },
            cc => 1, 
            ac => 1, 
            sn => 1,
        },
    },
});

my $fake_data_processed = $fake_data->process('numbers');
$test_machine->DATA_ITEM_STORE($fake_data_processed);
$test_machine->form_data_item();

{
    my $ticket = '32913';
    my $time = time();
    my $subscriber_test_machine = Test::Collection->new(
        name => 'subscribers',
    );
    $subscriber_test_machine->DATA_ITEM_STORE($fake_data->process('subscribers'));
    my $subscriber1 = $fake_data->create('subscribers')->[0];
    my $subscriber2 = $fake_data->create('subscribers')->[0];
    #print Dumper $subscriber1;
    $subscriber1->{content}->{alias_numbers} = [
        { cc=> '111', ac => $ticket, sn => $time },
        { cc=> '112', ac => $ticket, sn => $time },
        { cc=> '113', ac => $ticket, sn => $time },
    ];
    $subscriber1->{content}->{alias_numbers} = [
        { cc=> '211', ac => $ticket, sn => $time },
        { cc=> '212', ac => $ticket, sn => $time },
        { cc=> '213', ac => $ticket, sn => $time },
    ];
    my ($res,$content,$request);
    ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber1}{qw/content location/});
    ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber2}{qw/content location/});
    my $alias1 = $test_machine->get_item_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$subscriber1->{content}->{id});
    my $alias2 = $test_machine->get_item_hal('numbers','/api/numbers/?type=alias&subscriber_id='.$subscriber2->{content}->{id});
    $alias1
    $test_machine->request_put({subscriber_id => $subscriber2->{content}->{id}}, $alias1->{location})
    $test_machine->request_put({subscriber_id => $subscriber1->{content}->{id}}, $alias1->{location})

    #print Dumper $content;
    #my ($put_aliases1_out_res, $put_aliases1_get_res, $get_aliases1_res) = $subscriber_test_machine->put_and_get(
    #    $subscriber1, 
    #    {uri => '/api/numbers/?type=alias&subscriber_id='.$subscriber1->{content}->{id}},
    #    {skip_compare => 1}
    #);
    #print Dumper $get_aliases1_res->{content};
    #
    #my ($put_aliases2_out_res, $put_aliases2_get_res, $get_aliases2_res) = $subscriber_test_machine->put_and_get(
    #    $subscriber2, 
    #    {uri => '/api/numbers/?type=alias&subscriber_id='.$subscriber2->{content}->{id}},
    #    {skip_compare => 1}
    #);
    #print Dumper $get_aliases2_res->{content}->{_embedded}->{ngcp:numbers}->[0];
    #
    #my $alias1 = $get_aliases1_res->{content}->
    $test_machine->request_put();

    $subscriber_test_machine->clear_test_data_all();#fake data aren't registered in this test 
}

$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
$fake_data->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

# vim: set tabstop=4 expandtab:
