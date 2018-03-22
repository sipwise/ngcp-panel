use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;
use feature 'state';
#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'phonebookentries',
    QUIET_DELETION => 1,
);
my $subscriber_test_machine = Test::Collection->new(
    name => 'subscribers',
    QUIET_DELETION => 1,
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'phonebookentries' => {
        'data' => {
            customer_id          => sub { return shift->get_id('contracts',@_); },
            reseller_id          => sub { return shift->get_id('resellers',@_); },
            subscriber_id        => sub { return shift->get_id('subscribers',@_); },
            name                 => 'api_test phonebook username',
            number               => '111222333',
            shared               => '1',
        },
    },
});

$subscriber_test_machine->DATA_ITEM_STORE($fake_data->process('subscribers'));
$subscriber_test_machine->form_data_item();
$test_machine->DATA_ITEM_STORE($fake_data->process('phonebookentries'));
$test_machine->form_data_item();

my $remote_config = $test_machine->init_catalyst_config;

{#TT#34021
    $fake_data->{data}->{subscribers}->{data}->{administrative} = 1;
    my $subscriberadmin = $fake_data->create('subscribers')->[0];
    $test_machine->set_subscriber_credentials($subscriberadmin->{content});
    $test_machine->runas('subscriber');
    my $subscriberadmin_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{reseller_id};
        $_[0]->{subscriber_id} = $subscriberadmin->{content}->{id};
    } );
    test_phonebook_collection($subscriberadmin_phonebookentries_created, '/api/phonebookentries/?subscriber_id='.$subscriberadmin->{content}->{id});

    $fake_data->{data}->{subscribers}->{data}->{administrative} = 0;
    my $subscriber = $fake_data->create('subscribers')->[0];
    $test_machine->set_subscriber_credentials($subscriber->{content});
    $test_machine->runas('subscriber');
    my $subscriber_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{reseller_id};
        $_[0]->{subscriber_id} = $subscriber->{content}->{id};
    } );
    test_phonebook_collection($subscriber_phonebookentries_created, '/api/phonebookentries/?subscriber_id='.$subscriber->{content}->{id});

    $test_machine->runas('reseller');
    my $reseller_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{reseller_id};
        delete $_[0]->{subscriber_id};
        delete $_[0]->{shared};
    } );
    test_phonebook_collection($reseller_phonebookentries_created,'/api/phonebookentries/?customer_id='.$fake_data->{data}->{phonebookentries}->{data}->{customer_id});

    $test_machine->runas('admin');
    my $admin_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{subscriber_id};
        delete $_[0]->{shared};
    } );
    test_phonebook_collection($admin_phonebookentries_created,'/api/phonebookentries/?reseller_id='.$fake_data->{data}->{phonebookentries}->{data}->{reseller_id});
}

$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
$fake_data->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

sub test_phonebook_collection{
    my ($list,$collection_uri) = @_;
    $collection_uri //= 'api/phonebookentries';
    my $content_type = 'text/csv';
    my $content_type_old = clone $test_machine->content_type;
    $test_machine->content_type->{POST} = $content_type;
    $test_machine->get_collection_hal('phonebookentries',$collection_uri);

    my($req,$res,$content);
    $req = $test_machine->get_request_get( $collection_uri );
    $req->header('Accept' => $content_type);
    ($res,$content) = $test_machine->request($req);
    my $filename = "phonebook_list.csv";
    $test_machine->http_code_msg(200, "check response code", $res, $content);
    my $csv_data = $res->content;

    ($res,$content) = $test_machine->request_post($csv_data, $collection_uri.($collection_uri !~/\?/?'?':'&').'purge_existing=true');#
    $test_machine->http_code_msg(201, "check file upload", $res, $content);
    $test_machine->content_type($content_type_old);

    foreach my $entry (@$list) {
        $test_machine->check_get2put($entry);
        $test_machine->request_delete($entry->{location});
    }
}
# vim: set tabstop=4 expandtab:
