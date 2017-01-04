#!/usr/bin/perl

use strict;

use Data::Dumper;
use NGCP::Schema;
use NGCP::Panel::Utils::Email;
use UUID qw/generate unparse/;
use NGCP::Panel::Utils::DateTime;
use Test::MockObject;
use Log::Log4perl;
use Safe::Isa qw($_isa);

my $schema = NGCP::Schema->connect();
Log::Log4perl::init('/etc/ngcp-panel/logging.conf');
my $logger = Log::Log4perl->get_logger('NGCP::Panel');
my $c_mock = Test::MockObject->new();
my $user_mock = Test::MockObject->new();
$user_mock->set_always( 'roles' => 'reseller' );
$c_mock->set_always( 'log' => $logger )->set_always( 'model' => $schema )->set_always( 'user' => $user_mock );




my $contract_rs = $schema->resultset('contracts')->search( {
        #'me.create_timestamp' => { '>' => '2017-01-01' },
        'me.id' => { -in => [2858,2860,2861,2863,2865,2867,2869,2871,2873,2875,2877,2879,2881,2883,2885,2887,2889,2891,2893,2895] },
    },
);
foreach my $contract($contract_rs->all){
    my $subscribers_rs = $schema->resultset('voip_subscribers')->search( {
            'me.status' => { '!=' => 'terminated' },
            'me.contract_id' => $contract->id,
        }
    );
    foreach my $billing_subscriber ($subscribers_rs->all){
        if($contract->subscriber_email_template_id) {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);
            $billing_subscriber->password_resets->create({
                uuid => $uuid_string,
                # for new subs, let the link be valid for a year
                timestamp => NGCP::Panel::Utils::DateTime::current_local->epoch + 31536000,
            });
            #my $url = $c_mock->uri_for_action('/subscriber/recover_webpassword')->as_string . '?uuid=' . $uuid_string;
            my $url = 'https://127.0.0.1:1443' . '?uuid=' . $uuid_string;
            NGCP::Panel::Utils::Email::new_subscriber($c_mock, $billing_subscriber, $url);
        }
    }
}


1;