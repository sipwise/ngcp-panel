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

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'numbers' => {
        'data' => {
            subscriber_id  => sub { return shift->get_id('customers',@_); },
            cc => 1, 
            ac => 1, 
            sn => 1,
            
        },
    },
});

my $fake_data_processed = $fake_data->process('subscribers');
$test_machine->DATA_ITEM_STORE($fake_data_processed);
$test_machine->form_data_item();

{
    my $subscriber_test_machine = Test::Collection->new(
        name => 'subscribers',
    );
    $fake_data->load_data_from_script('subscribers');
}

sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

# vim: set tabstop=4 expandtab:
