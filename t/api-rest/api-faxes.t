use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

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
            faxfile => [ dirname($0).'/resources/empty.txt' ],
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



{
    my ($res, $content, $req) = $test_machine->check_item_post();
    if(422 == $res->code){
        $test_machine->http_code_msg(422, "check faxserver feature state: disabled", $res, $content);
        my $inactive_feature_msg = "Faxserver feature is not active";
        if( $content->{message} =~ /$inactive_feature_msg/ ){
        #some weird construction of the tests, but in case of inactive faxes feature and inactive faxes for the  userboth response code will be 422.
        #if feature is inactive on the application level - there is nothing to test more
        #so added this pseudo test just to place it here. Really don't like it.
            ok($content->{message} =~ /$inactive_feature_msg/, "check error message in body: $inactive_feature_msg");
            done_testing;
            exit();
        }
    }
}



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

#$test_machine->check_bundle();
#$test_machine->check_get2put( sub { $_[0] = { json => JSON::to_json($_[0]), 'faxfile' =>  $test_machine->DATA_ITEM_STORE->{faxfile} }; } );

done_testing;

# vim: set tabstop=4 expandtab:
