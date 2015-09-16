#use Sipwise::Base;
use strict;

#use Moose;
use Sipwise::Base;
use Test::Collection;
use Test::FakeData;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
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
            my ($self,$name) = @_;
            my $prev_params = $self->test_machine->get_cloned('content_type');
            @{$self->test_machine->content_type}{qw/POST PUT/} = (('multipart/form-data') x 2);
            $self->test_machine->check_create_correct(1);
            $self->test_machine->set(%$prev_params);
        },
        'no_delete_available' => 1,
    },
});
my $test_machine = Test::Collection->new(
    name => 'faxes',
    embedded => [qw/subscribers/]
);
$test_machine->DATA_ITEM_STORE($fake_data->process('faxes'));
@{$test_machine->content_type}{qw/POST PUT/}    = (('multipart/form-data') x 2);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS)};


$test_machine->form_data_item( );
$test_machine->check_create_correct( 1 );
$test_machine->check_bundle();
#$test_machine->check_get2put( sub { $_[0] = { json => JSON::to_json($_[0]), 'faxfile' =>  $test_machine->DATA_ITEM_STORE->{faxfile} }; } );

done_testing;

# vim: set tabstop=4 expandtab:
