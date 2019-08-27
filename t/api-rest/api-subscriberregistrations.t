use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

use NGCP::Panel::Utils::DateTime;


#init test_machine
my $test_machine = Test::Collection->new(
    name => 'subscriberregistrations',
    ALLOW_EMPTY_COLLECTION => 1,
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $expires = NGCP::Panel::Utils::DateTime::current_local();

$fake_data->set_data_from_script({
    'subscriberregistrations' => {
        data => {
           'contact' => 'test',
           'expires' => $expires->ymd('-') . ' ' . $expires->hms(':'),
           'q' => 0.5,
           'subscriber_id' => sub { return shift->get_id('subscribers', @_); },
        },
        'update_change_fields' => [qw/_links expires id/],#expires seems like timezone difference
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('subscriberregistrations'));
$test_machine->form_data_item( );

# create 3 new vouchers from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{contact} .= time().'_'.$_[1]->{i} ; } );

#order of [check_bundle, check_get2put ] is important here: 
#subscriberregistrations really is just a wrapper arounf kamailio rpc calls, 
#and update of the existing item is made as delete+create. So, on every PUT or PATCH we delete item, and create new. 
#It makes internal Collection list of created items misordered with real data in db, 
#because Collection just keeps all created item, and doesn't try to recreate them on every update
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

$test_machine->check_create_correct( 1, sub{ $_[0]->{contact} .= time().'_'.$_[1]->{i} ; } );

for (my $i=0; $i < 15; $i++) {
    $test_machine->check_get2put(undef, undef, { ignore_fields => [qw/id _links/] });
}
$test_machine->clear_data_created();

$test_machine->check_create_correct( 1, sub{ $_[0]->{contact} .= time().'_'.$_[1]->{i} ; } );
{
    my($res, $content) = $test_machine->check_item_post(sub{$_[0]->{q} = 2;$_[0]->{contact} .= time().'_MT14779_1' ;});
    $test_machine->http_code_msg(422, "check creation of the subscriber registration with q > 1. MT#14779",$res,$content);
}
{
    my($res, $content) = $test_machine->check_item_post(sub{$_[0]->{q} = -2;$_[0]->{contact} .= time().'_MT14779_2' ;});
    $test_machine->http_code_msg(422, "check creation of the subscriber registration with q < -1. MT#14779",$res,$content);
}
{
    # Default value should be used.
    my($res, $content) = $test_machine->check_item_post(sub{delete $_[0]->{q};$_[0]->{contact} .= time().'_MT14779_3';});
    $test_machine->http_code_msg(201, "check creation of the subscriber registration without q. MT#14779.",$res,$content);
}
{
    my($res, $content) = $test_machine->check_item_post(sub{delete $_[0]->{expires};$_[0]->{contact} .= time().'_MT14891_1';});
    $test_machine->http_code_msg(422, "check creation of the subscriber registration without required expires. MT#14891.",$res,$content);
}

#api doesn't deny extra fields
#{
#    my($res, $content) = $test_machine->check_item_post(sub{$_[0]->{user_agent} = 'Test User Agent';$_[0]->{contact} .= time().'_MT14789' ;});
#    $test_machine->http_code_msg(422, "check creation of the subscriber registration with already removed "user_agent". MT#14789.",$res,$content);
#}

$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
