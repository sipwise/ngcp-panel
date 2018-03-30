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
$test_machine->QUERY_PARAMS('reseller_id='.$fake_data->{data}->{phonebookentries}->{data}->{reseller_id});
my $admin_phonebookentries_created = $test_machine->check_create_correct(2, sub {
    delete $_[0]->{customer_id};
    delete $_[0]->{subscriber_id};
    delete $_[0]->{shared};
    $_[0]->{number} = time() + seq();
} );

$test_machine->check_bundle();
$test_machine->QUERY_PARAMS('');

{#TT#34021
    diag("create subscriber of other customer of other reseller");
    my $fake_data_other_customer = Test::FakeData->new(keep_db_data => 1);
    $fake_data_other->{data}->{customers}->{data}->{external_id} = 'not_default_one';
    $fake_data_other->{data}->{resellers}->{data}->{name} = 'not_default_one';
    my $subscriber_other_customer = $fake_data_other_customer->create('subscribers')->[0];
    my $subscriber_other_phonebookentries = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{reseller_id};
        $_[0]->{subscriber_id} = $subscriber_other_customer->{content}->{customer_id};
        $_[0]->{number} = time() + seq();
    } );
    my $customer_other_phonebookentries = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{subscriber_id};
        delete $_[0]->{reseller_id};
        $_[0]->{customer_id} = $subscriber_other_customer->{content}->{id};
        $_[0]->{number} = time() + seq();
    } );
    my $reseller_other_phonebookentries = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{subscriber_id};
        delete $_[0]->{customer_id};
        $_[0]->{reseller_id} = $fake_data_other->{data}->{customers}->{data}->{reseller_id};
        $_[0]->{number} = time() + seq();
    } );

    $fake_data->{data}->{subscribers}->{data}->{administrative} = 1;
    my $subscriberadmin = $fake_data->create('subscribers')->[0];
    $test_machine->set_subscriber_credentials($subscriberadmin->{content});
    $test_machine->runas('subscriber');
    diag("\n\n\nSUBSCRIBERADMIN ".$subscriberadmin->{content}->{id}.":");
    diag("attempt to create using other customer subscriber:");
    my($res,$content) = $test_machine->check_item_post();
    $test_machine->http_code_msg(422, "Check that we cant send a fax in a name of other customers subscriber",$res,$content);
    diag("create items one-by-one:");
    my $subscriberadmin_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{reseller_id};
        $_[0]->{subscriber_id} = $subscriberadmin->{content}->{id};
        $_[0]->{number} = time() + seq();
    } );
    test_phonebook_collection($subscriberadmin_phonebookentries_created, '/api/phonebookentries/?subscriber_id='.$subscriberadmin->{content}->{id});

    $fake_data->{data}->{subscribers}->{data}->{administrative} = 0;
    my $subscriber = $fake_data->create('subscribers')->[0];
    $test_machine->set_subscriber_credentials($subscriber->{content});
    $test_machine->runas('subscriber');
    diag("\n\n\nSUBSCRIBER ".$subscriber->{content}->{id}.":");
    diag("create items one-by-one:");
    my $subscriber_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{reseller_id};
        $_[0]->{subscriber_id} = $subscriber->{content}->{id};
        $_[0]->{number} = time() + seq();
    } );
    test_phonebook_collection($subscriber_phonebookentries_created, '/api/phonebookentries/?subscriber_id='.$subscriber->{content}->{id});

    $test_machine->runas('reseller');
    diag("\n\n\nRESELLER :");
    diag("create items one-by-one:");
    my $reseller_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{reseller_id};
        delete $_[0]->{subscriber_id};
        delete $_[0]->{shared};
        $_[0]->{number} = time() + seq();
    } );
    test_phonebook_collection($reseller_phonebookentries_created,'/api/phonebookentries/?customer_id='.$fake_data->{data}->{phonebookentries}->{data}->{customer_id});

    $test_machine->runas('admin');
    diag("\n\n\nADMIN :");
    diag("create items one-by-one:");
    my $admin_phonebookentries_created = $test_machine->check_create_correct(2, sub {
        delete $_[0]->{customer_id};
        delete $_[0]->{subscriber_id};
        delete $_[0]->{shared};
        $_[0]->{number} = time() + seq();
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
    diag("collection_uri: $collection_uri;");
    my $content_type = 'text/csv';
    my $content_type_old = clone $test_machine->content_type;
    $test_machine->content_type->{POST} = $content_type;
    diag("get collection:");
    $test_machine->get_collection_hal('phonebookentries',$collection_uri);

    my($req,$res,$content);
    $req = $test_machine->get_request_get( $collection_uri );
    $req->header('Accept' => $content_type);
    diag("download csv:");
    $res = $test_machine->request($req);
    my $csv_data = $res->content;
    my $filename = "phonebook_list.csv";
    $test_machine->http_code_msg(200, "check response code", $res, $csv_data);
    ok(length($csv_data) > 0, "Check that downloaded csv is not empty.");
    diag("upload csv with purge_existing = 0:");
    ($res,$content) = $test_machine->request_post($csv_data, $collection_uri);#
    $test_machine->http_code_msg(201, "check file upload", $res, $content);
    $test_machine->content_type(clone $content_type_old);

    diag("go through list:");
    foreach my $entry (@$list) {
        $test_machine->check_get2put($entry);
        $test_machine->request_delete($entry->{location});
    }

    $test_machine->content_type->{POST} = $content_type;
    diag("upload csv with purge_existing = 1:");
    ($res,$content) = $test_machine->request_post($csv_data, $collection_uri.($collection_uri !~/\?/?'?':'&').'purge_existing=true');#
    $test_machine->http_code_msg(201, "check file upload", $res, $content);
    $test_machine->content_type(clone $content_type_old);
}

sub seq{
    my ($number) = @_;
    state $seq = 0;
    $number //= 0;
    return $number + $seq++;
}
# vim: set tabstop=4 expandtab:
