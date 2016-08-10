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
            number      => sub { 
                my $self = shift; 
                $self->get_id('subscribers',@_);
                my $data;
                if($self->loaded->{subscribers}->[0]){
                    $data = $self->loaded->{subscribers}->[0]->{content};
                }else{
                    (undef, $data, undef) = $self->test_machine->request_get($self->created->{subscribers}->[0]->{location});
                }
                return join('',@{$data->{primary_number}}{qw/cc ac sn/});
            },
            x2_host     => '127.0.0.1',
            x2_password => '',
            x2_port     => '1443',
            x2_user     => '',
            x3_host     => '',
            x3_port     => 1,#todo: empty makes 500, should be fixed
            x3_required => 0,
        },
        'query' => ['liid'],
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('interceptions'));
$test_machine->form_data_item();

{
#18561
    diag("18561: Forbid to change liid;\n\n");
    my ($res_create, $content_create) = $test_machine->request_post();
    is($res_create->code, 201, "create interception ");
    my $location = $test_machine->base_uri.$res_create->header('Location');
    my($res_get, $content_get_created, $req_get) = $test_machine->request_get($location);
    my($res,$content,$request) = $test_machine->request_put($content_get_created, $location);
    $test_machine->http_code_msg(200, "Check that PUT with the same liid is OK", $res, $content);
    $content_get_created->{liid} .= '1';
    ($res,$content,$request) = $test_machine->request_put($content_get_created, $location);
    $test_machine->http_code_msg(422, "Check that PUT with different liid is forbidden", $res, $content);
    ok($content->{message} =~ /liid can not be changed/, "check error message in body");
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
}

$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
undef $fake_data;
done_testing;


# vim: set tabstop=4 expandtab:
