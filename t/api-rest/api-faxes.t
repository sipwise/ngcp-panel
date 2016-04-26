use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use File::Temp qw/tempfile/;
use File::Basename;


#init test_machine
my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'faxes' => {
        'data' => {
            json => {
                subscriber_id  => sub { return shift->get_id('subscribers',@_); },
                destination => "Cisco",
            },
            faxfile => [ (tempfile())[1] ],
        },
        'create_special'=> sub {
            my ($self,$name,$test_machine) = @_;
            my $prev_params = $test_machine->get_cloned('content_type');
            @{$test_machine->content_type}{qw/POST PUT/} = (('multipart/form-data') x 2);
            $test_machine->check_create_correct(1);
            $test_machine->set(%$prev_params);
        },
        'no_delete_available' => 1,
    },
});
my $test_machine = Test::Collection->new(
    name => 'faxes',
    embedded_resources => [qw/subscribers/]
);

my $remote_config = $test_machine->init_catalyst_config;
if( !$remote_config->{config}->{features}->{faxserver} ){
    $remote_config->{config}->{features}->{faxserver} //= 0;
    is($remote_config->{config}->{features}->{faxserver},0,"axserver feature isn't enabled");
}else{

    @{$test_machine->content_type}{qw/POST PUT/}    = (('multipart/form-data') x 2);
    $test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
    $test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS)};

    $test_machine->DATA_ITEM_STORE($fake_data->process('faxes'));
    $test_machine->form_data_item();


    {
        my $test_machine_aux = Test::Collection->new(name => 'faxserversettings');
        my $uri = $test_machine_aux->get_uri($test_machine->DATA_ITEM->{json}->{subscriber_id});
        my($res,$faxserversettings,$req) = $test_machine_aux->check_item_get($uri);
        $faxserversettings->{active} = 1;
        $faxserversettings->{password} = 'aaa111';
        $test_machine_aux->request_put($faxserversettings,$uri);
    }

    $test_machine->resource_fill_file($test_machine->DATA_ITEM->{faxfile}->[0]);
    $test_machine->check_create_correct( 1 );
    $test_machine->resource_clear_file($test_machine->DATA_ITEM->{faxfile}->[0]);

    delete $test_machine->DATA_ITEM->{faxfile};
    $test_machine->DATA_ITEM->{json}->{data}="äöüß";
    $test_machine->form_data_item();
    $test_machine->check_create_correct( 1 );
}

#$test_machine->check_bundle();
#$test_machine->check_get2put( sub { $_[0] = { json => JSON::to_json($_[0]), 'faxfile' =>  $test_machine->DATA_ITEM_STORE->{faxfile} }; } );

$test_machine->clear_test_data_all();
done_testing;

undef $fake_data;
undef $test_machine;

# vim: set tabstop=4 expandtab:
