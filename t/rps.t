use strict;

use Test::MockObject;
use NGCP::Schema;
use Log::Log4perl;
use NGCP::Panel::Utils::DeviceBootstrap;
use Data::Dumper;

Log::Log4perl::init('/etc/ngcp-panel/logging.conf');
my $logger = Log::Log4perl->get_logger('NGCP::Panel');
my $schema = NGCP::Schema->connect();
my $dbh = $schema->storage->dbh;
my $c_mock = Test::MockObject->new();
my $user_mock = Test::MockObject->new();
$user_mock->set_always( 'roles' => 'reseller' );
$c_mock->set_always( 'log' => $logger )->set_always( 'model' => $schema )->set_always( 'user' => $user_mock );

my $params_pre = {
    'redirect_panasonic' => {
        'credentials' => {
            'password' => 'aRRwgzVbmJ',
            'user' => 'EU-Sipwise'
        },
        'mac' => 'bcc34206f766',
    },
    'redirect_yealink' => {
        'credentials' => {
            'user' => 'agranig@sipwise.com',
            'password' => 'aRRwgzVbmJ',
        },
    },
    'redirect_polycom' => {
        'credentials' => {
            'user' => '2001587715',
            'password' => 'ohv$0602',
        },
        'redirect_params' => {
            'profile' => 'test_prov_1'
        },
    },
    'redirect_snom' => {
        'credentials' => {
            'user' => 'sipwise',
            'password' => 'GQf8K09J',
        },
    },
    #redirect_patton - not implemented
    #redirect_innovaphone - not implemented
    #redirect_grandstream - credentials ?
};

foreach my $method (keys %$params_pre){
    my $response;
    my $param_pre = $params_pre->{$method};
    my $params = {
        'c' => $c_mock,
        'bootstrap_method' => $method,
        'credentials'      => $param_pre->{credentials},
        'mac'              => $param_pre->{mac} // 'aabbccddeeff',
        'redirect_params'  => $param_pre->{redirect_params} // {},
        'redirect_uri'     => $param_pre->{redirect_uri} // 'https://127.0.0.1:1443/',
    };
    foreach my $action (qw/register_model register unregister unregister_model/){
        $response = NGCP::Panel::Utils::DeviceBootstrap::_dispatch($c_mock, $action, $params);
        print Dumper $response;
    }
}

__DATA__

$VAR1 = [
          [
            'NGCP::Panel::Utils::DeviceBootstrap::_dispatch',
            'register',
            {
              'bootstrap_method' => 'redirect_panasonic',
              'mac_old' => undef,
              'credentials' => {
                                 'password' => 'aRRwgzVbmJ',
                                 'user' => 'EU-Sipwise'
                               },
              'mac' => 'bcc34206f766',
              'redirect_params' => {},
              'redirect_uri' => ''
            },
            '/_dispatch'
          ]
        ];
$VAR1 = [
          [
            'NGCP::Panel::Utils::DeviceBootstrap::_dispatch',
            'register',
            {
              'credentials' => {
                                 'password' => 'ohv$0602',
                                 'user' => '2001587715'
                               },
              'mac' => 'aabbccddeeff',
              'mac_old' => undef,
              'redirect_params' => {
                                     'profile' => 'test_prov_1'
                                   },
              'bootstrap_method' => 'redirect_polycom',
              'redirect_uri' => ''
            },
            '/_dispatch'
          ]
        ];
# vim: set tabstop=4 expandtab: