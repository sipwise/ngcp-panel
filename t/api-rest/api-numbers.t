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
    my ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber1}{qw/content location/});
    #print Dumper $content;
    #my ($put_res, $get_res) = $subscriber_test_machine->check_put2get($subscriber1, undef, {ignore_fields => modify_timestamp});
}

sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

# vim: set tabstop=4 expandtab:
