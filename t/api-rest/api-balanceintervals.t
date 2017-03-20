use strict;
use warnings;
use threads qw();
use threads::shared qw();

#use Sipwise::Base; #causes segfault when creating threads..
use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;
use Time::HiRes; #prevent warning from Time::Warp
use Time::Warp qw();
use DateTime::Format::Strptime;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Storable;
use Text::Table;
use Text::Wrap;
$Text::Wrap::columns = 58;
#use Sys::CpuAffinity;

use JSON::PP;
use LWP::Debug;

BEGIN {
    unshift(@INC,'../../lib');
}
use NGCP::Panel::Utils::DateTime qw();
#use NGCP::Panel::Utils::ProfilePackages qw(); #since it depends on Utils::Subscribers and thus Sipwise::Base, importin it causes segfault when creating threads..

my $is_local_env = 0;
my $disable_parallel_catchup = 1;
my $disable_hourly_intervals = 1;
#my $enable_profile_packages = NGCP::Panel::Utils::ProfilePackages::ENABLE_PROFILE_PACKAGES;
#my $enable_profile_packages = 1;

use Config::General;
my $catalyst_config;
if ($is_local_env) {
    $catalyst_config = Config::General->new("../../ngcp_panel.conf");
} else {
    #taken 1:1 from /lib/NGCP/Panel.pm
    my $panel_config;
    for my $path(qw#/etc/ngcp-panel/ngcp_panel.conf etc/ngcp_panel.conf ngcp_panel.conf#) {
        if(-f $path) {
            $panel_config = $path;
            last;
        }
    }
    $panel_config //= 'ngcp_panel.conf';
    $catalyst_config = Config::General->new($panel_config);
}
my %config = $catalyst_config->getall();

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);
use Test::Collection;
$ua = Test::Collection->new()->ua();

my $req_identifier;
my $infinite_future;

{
    my $future = NGCP::Panel::Utils::DateTime::infinite_future;
    my $past = NGCP::Panel::Utils::DateTime::infinite_past;
    my $now = NGCP::Panel::Utils::DateTime::current_local;

    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T',
    );
    $infinite_future = $dtf->format_datetime($future);
    is($infinite_future,'9999-12-31 23:59:59','check if infinite future is 9999-12-31 23:59:59');
    is($dtf->format_datetime($past),'1000-01-01 00:00:00','check if infinite past is 1000-01-01 00:00:00');

    foreach my $offset ((0,'+'. 80*365*24*60*60 .'s','-'. 80*365*24*60*60 .'s')) {

        my ($fake_now,$offset_label);
        if ($offset) {
            _set_time($offset);
            $fake_now = NGCP::Panel::Utils::DateTime::current_local;
            my $delta = $fake_now->epoch - $now->epoch;
            my $delta_offset = substr($offset,0,length($offset)-2) * 1;
            ok(abs($delta) > abs($delta_offset) && abs($delta_offset) > 0,"'Great Scott!'");
            ok($delta > $delta_offset,'check fake time offset of ' . $offset . ': ' . $delta) if $delta_offset > 0;
            ok(-1 * $delta > -1 * $delta_offset,'check fake time offset of ' . $offset . ': ' . $delta) if $delta_offset < 0;
            $offset_label = 'fake time offset: ' . $offset . ': ';
        } else {
            $fake_now = $now;
            $offset_label = '';
        }

        ok($future > $fake_now,$offset_label . 'future is greater than now');
        ok(!($future < $fake_now),$offset_label . 'future is not smaller than now');

        ok($past < $fake_now,$offset_label . 'past is smaller than now');
        ok(!($past > $fake_now),$offset_label . 'past is not greater than now');

        ok($future->epoch > $fake_now->epoch,$offset_label . 'future is greater than now (epoch)');
        ok(!($future->epoch < $fake_now->epoch),$offset_label . 'future is not smaller than now (epoch)');

        ok($past->epoch < $fake_now->epoch,$offset_label . 'past is smaller than now (epoch)');
        ok(!($past->epoch > $fake_now->epoch),$offset_label . 'past is not greater than now (epoch)');
    }
    _set_time();
}

my $t = time;
my $default_reseller_id = 1;

my $default_custcontact = _create_customer_contact();

$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    domain => 'test' . ($t-1) . '.example.org',
    reseller_id => $default_reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test domain");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test domain");
my $domain = JSON::from_json($res->decoded_content);


my %customer_map :shared = ();
my %subscriber_map :shared = ();

my $customer_contact_map = {};
my $package_map = {};
my $voucher_map = {};
my $profile_map = {};

my $billingprofile = _create_billing_profile("test_default");

my $tb;
my $tb_cnt;
my $gantt_events;

if (_get_allow_fake_client_time()) { # && $enable_profile_packages) {

    #goto SKIP;
    #goto THREADED;
    if ('Europe/Vienna' eq NGCP::Panel::Utils::DateTime::current_local()->time_zone->name) {
        if (!$disable_hourly_intervals) {
            my $package = _create_profile_package('create','hour',1);

            {
                my $dt = NGCP::Panel::Utils::DateTime::from_string('2015-03-29 01:27:00');
                ok(!$dt->is_dst(),NGCP::Panel::Utils::DateTime::to_string($dt)." is not in daylight saving time (winter)");
                _set_time($dt);
                my $customer = _create_customer($package,'hourly_interval_dst_at');

                _check_interval_history($customer,[
                    { start => '2015-03-29 00:00:00', stop => '2015-03-29 00:59:59' },
                    { start => '2015-03-29 01:00:00', stop => '2015-03-29 01:59:59' },
                ]);

                $dt = NGCP::Panel::Utils::DateTime::from_string('2015-03-29 03:27:00');
                ok($dt->is_dst(),NGCP::Panel::Utils::DateTime::to_string($dt)." is in daylight saving time (summer)");
                _set_time($dt);

                _check_interval_history($customer,[
                    { start => '2015-03-29 00:00:00', stop => '2015-03-29 00:59:59' },
                    { start => '2015-03-29 01:00:00', stop => '2015-03-29 01:59:59' },
                    #{ start => '2015-03-29 02:00:00', stop => '2015-03-29 02:59:59' }, #a dead one
                    { start => '2015-03-29 03:00:00', stop => '2015-03-29 03:59:59' },
                ]);

                _set_time();
            }
            {
                my $dt = NGCP::Panel::Utils::DateTime::from_string('2015-10-25 01:27:00');
                ok($dt->is_dst(),NGCP::Panel::Utils::DateTime::to_string($dt)." is in daylight saving time (summer)");
                _set_time($dt);
                my $customer = _create_customer($package,'hourly_interval_dst_at');

                _check_interval_history($customer,[
                    { start => '2015-10-25 00:00:00', stop => '2015-10-25 00:59:59' },
                    { start => '2015-10-25 01:00:00', stop => '2015-10-25 01:59:59' },
                ]);

                #$dt = NGCP::Panel::Utils::DateTime::from_string('2015-10-25 02:27:00');
                #ok(!$dt->is_dst(),NGCP::Panel::Utils::DateTime::to_string($dt)." is not in daylight saving time (winter)");
                #_set_time($dt);
                #
                #_check_interval_history($customer,[
                #    { start => '2015-10-25 00:00:00', stop => '2015-10-25 00:59:59' },
                #    { start => '2015-10-25 01:00:00', stop => '2015-10-25 01:59:59' },
                #    { start => '2015-10-25 02:00:00', stop => '2015-10-25 02:59:59' },
                #]);

                $dt = NGCP::Panel::Utils::DateTime::from_string('2015-10-25 03:27:00');
                ok(!$dt->is_dst(),NGCP::Panel::Utils::DateTime::to_string($dt)." is not in daylight saving time (winter)");
                _set_time($dt);

                _check_interval_history($customer,[
                    { start => '2015-10-25 00:00:00', stop => '2015-10-25 00:59:59' },
                    { start => '2015-10-25 01:00:00', stop => '2015-10-25 01:59:59' },
                    { start => '2015-10-25 02:00:00', stop => '2015-10-25 02:59:59' },
                    { start => '2015-10-25 03:00:00', stop => '2015-10-25 03:59:59' },
                ]);

                _set_time();
            }
        }
    } else {
        diag("time zone '" . NGCP::Panel::Utils::DateTime::current_local()->time_zone->name . "', skipping DST test");
    }

    if (!$disable_hourly_intervals) {
        my $package = _create_profile_package('create','hour',1);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-09-02 01:59:41'));

        my $customer = _create_customer($package,'hourly_interval');

        _check_interval_history($customer,[
            { start => '2015-09-02 00:00:00', stop => '2015-09-02 00:59:59' },
            { start => '2015-09-02 01:00:00', stop => '2015-09-02 01:59:59' },
        ]);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-09-02 02:00:01'));

        _check_interval_history($customer,[
            { start => '2015-09-02 00:00:00', stop => '2015-09-02 00:59:59' },
            { start => '2015-09-02 01:00:00', stop => '2015-09-02 01:59:59' },
            { start => '2015-09-02 02:00:00', stop => '2015-09-02 02:59:59' },
        ]);

        _set_time();
    }

    if (!$disable_hourly_intervals) {
        my $package = _create_profile_package('create','minute',1);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-09-03 00:01:41'));

        my $customer = _create_customer($package,'minute_interval');

        _check_interval_history($customer,[
            { start => '2015-09-03 00:00:00', stop => '2015-09-03 00:00:59' },
            { start => '2015-09-03 00:01:00', stop => '2015-09-03 00:01:59' },
        ]);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-09-03 00:02:01'));

        _check_interval_history($customer,[
            { start => '2015-09-03 00:00:00', stop => '2015-09-03 00:00:59' },
            { start => '2015-09-03 00:01:00', stop => '2015-09-03 00:01:59' },
            { start => '2015-09-03 00:02:00', stop => '2015-09-03 00:02:59' },
        ]);

        _set_time();
    }

    #SKIP:
    {
        my $profile_initial = _create_billing_profile('UNDERRUN1_INITIAL',prepaid => 0);
        my $profile_topup = _create_billing_profile('UNDERRUN1_TOPUP',prepaid => 0);
        my $profile_underrun = _create_billing_profile('UNDERRUN1_UNDERRUN',prepaid => 1);

        my $package = _create_profile_package('1st','month',1, initial_balance => 100,
                carry_over_mode => 'discard', underrun_lock_threshold => 50, underrun_lock_level => 4, underrun_profile_threshold => 50,
                initial_profiles => [ { profile_id => $profile_initial->{id}, }, ],
                topup_profiles => [ { profile_id => $profile_topup->{id}, }, ],
                underrun_profiles => [ { profile_id => $profile_underrun->{id}, }, ],
                );

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-14 13:00:00'));

        my $customer = _create_customer($package,'underrun_1');
        my $subscriber = _create_subscriber($customer,'of customer underrun_1');

        _check_interval_history($customer,[
            { start => '2015-06-01 00:00:00', stop => '2015-06-30 23:59:59', cash => 1, profile => $profile_initial->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),undef,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_cash_balance($customer,0.51);

        _check_interval_history($customer,[
            { start => '2015-06-01 00:00:00', stop => '2015-06-30 23:59:59', cash => 0.51, profile => $profile_initial->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),undef,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_cash_balance($customer,0.49);

        _check_interval_history($customer,[
            { start => '2015-06-01 00:00:00', stop => '2015-06-30 23:59:59', cash => 0.49, profile => $profile_initial->{id} },
        ]);
        is(_get_actual_billing_profile_id($customer),$profile_underrun->{id},"check customer id " . $customer->{id} . " actual billing profile id");
        is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-14 13:00:00'));

        _perform_topup_cash($subscriber,0.5);

        _check_interval_history($customer,[
            { start => '2015-06-01 00:00:00', stop => '2015-06-30 23:59:59', cash => 0.49, profile => $profile_initial->{id} },
            { start => '2015-07-01 00:00:00', stop => '2015-07-31 23:59:59', cash => 0.5, profile => $profile_underrun->{id} },
        ]);
        is(_get_actual_billing_profile_id($customer),$profile_topup->{id},"check customer id " . $customer->{id} . " actual billing profile id");
        is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time();

    }

    {
        #underrun due to switching to package with lower thresholds:
        my $profile_initial_1 = _create_billing_profile('UNDERRUN2_INITIAL_1');
        my $profile_underrun_1 = _create_billing_profile('UNDERRUN2_UNDERRUN_1');

        my $profile_initial_2 = _create_billing_profile('UNDERRUN2_INITIAL_2');
        my $profile_topup_2 = _create_billing_profile('UNDERRUN2_TOPUP_2');
        my $profile_underrun_2 = _create_billing_profile('UNDERRUN2_UNDERRUN_2');

        my $package_1 = _create_profile_package('1st','month',1, initial_balance => 49,
                carry_over_mode => 'discard', underrun_lock_threshold => 50, underrun_lock_level => 4, underrun_profile_threshold => 52,
                initial_profiles => [ { profile_id => $profile_initial_1->{id}, }, ],
                underrun_profiles => [ { profile_id => $profile_underrun_1->{id}, }, ],
                );

        my $package_2 = _create_profile_package('topup_interval','month',1, initial_balance => 99,
            carry_over_mode => 'carry_over', underrun_lock_threshold => 51, underrun_lock_level => 4, underrun_profile_threshold => 51,
            initial_profiles => [ { profile_id => $profile_initial_2->{id}, }, ],
            underrun_profiles => [ { profile_id => $profile_underrun_2->{id}, }, ],
        );
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-23 13:00:00'));

        my $customer = _create_customer($package_1,'1');
        my $subscriber = _create_subscriber($customer,'of customer 1');

        _check_interval_history($customer,[
            { start => '2015-01-01 00:00:00', stop => '2015-01-31 23:59:59', cash => 0.49, profile => $profile_underrun_1->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-23 14:00:00'));
        _switch_package($customer,$package_2);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-24 13:00:00'));

        _perform_topup_cash($subscriber,0.01);

        _check_interval_history($customer,[
            { start => '2015-01-01 00:00:00', stop => '~2015-01-24 13:00:00', cash => 0.49, profile => $profile_underrun_1->{id} },
            { start => '~2015-01-24 13:00:00', stop => '~2015-02-24 13:00:00', cash => 0.5, profile => $profile_underrun_2->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time();
    }

    {

        my $profile_initial = _create_billing_profile('UNDERRUN3_INITIAL');
        my $profile_topup = _create_billing_profile('UNDERRUN3_TOPUP');
        my $profile_underrun = _create_billing_profile('UNDERRUN3_UNDERRUN');

        my $package = _create_profile_package('topup','month',1,
                carry_over_mode => 'carry_over', underrun_lock_threshold => 1000, underrun_lock_level => 4, underrun_profile_threshold => 1000,
                topup_lock_level => 0,
                initial_profiles => [ { profile_id => $profile_initial->{id}, }, ],
                topup_profiles => [ { profile_id => $profile_topup->{id}, }, ],
                underrun_profiles => [ { profile_id => $profile_underrun->{id}, }, ],
                );

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-20 13:00:00'));

        my $customer = _create_customer($package,'2');
        my $subscriber = _create_subscriber($customer,'of customer 2');

        _check_interval_history($customer,[
            { start => '~2015-07-20 13:00:00', stop => $infinite_future, cash => 0, profile => $profile_underrun->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-20 13:00:10'));

        _perform_topup_cash($subscriber,5);
        _check_interval_history($customer,[
            { start => '~2015-07-20 13:00:00', stop => '~2015-07-20 13:00:10', cash => 0, profile => $profile_underrun->{id} },
            { start => '~2015-07-20 13:00:10', stop => $infinite_future, cash => 5, profile => $profile_underrun->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),undef,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-20 13:00:20'));
        _perform_topup_cash($subscriber,5);
        _check_interval_history($customer,[
            { start => '~2015-07-20 13:00:00', stop => '~2015-07-20 13:00:10', cash => 0, profile => $profile_underrun->{id} },
            { start => '~2015-07-20 13:00:10', stop => '~2015-07-20 13:00:20', cash => 5, profile => $profile_underrun->{id} },
            { start => '~2015-07-20 13:00:20', stop => $infinite_future, cash => 10, profile => $profile_topup->{id} },
        ]);
        is(_get_subscriber_lock_level($subscriber),undef,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time();
    }

    {
        #_start_recording();
        my $network_x = _create_billing_network_x();
        my $network_y = _create_billing_network_y();

        my $profile_base_any = _create_billing_profile('BASE_ANY_NETWORK');
        my $profile_base_x = _create_billing_profile('BASE_NETWORK_X');
        my $profile_base_y = _create_billing_profile('BASE_NETWORK_Y');

        my $profile_silver_x = _create_billing_profile('SILVER_NETWORK_X');
        my $profile_silver_y = _create_billing_profile('SILVER_NETWORK_Y');

        my $profile_gold_x = _create_billing_profile('GOLD_NETWORK_X');
        my $profile_gold_y = _create_billing_profile('GOLD_NETWORK_Y');

        my $base_package = _create_base_profile_package($profile_base_any,$profile_base_x,$profile_base_y,$network_x,$network_y);
        my $silver_package = _create_silver_profile_package($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y);
        my $extension_package = _create_extension_profile_package($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y);
        my $gold_package = _create_gold_profile_package($base_package,$profile_gold_x,$profile_gold_y,$network_x,$network_y);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-05 13:00:00'));
        my $customer_A = _create_customer($base_package,'A');
        my $subscriber_A = _create_subscriber($customer_A,'of customer A');
        #_start_recording();
        my $v_silver_1 = _create_voucher(10,'SILVER_1_'.$t,undef,$silver_package);
        #print _stop_recording();

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-21 13:00:00'));

        _perform_topup_voucher($subscriber_A,$v_silver_1);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-10-01 13:00:00'));

        _check_interval_history($customer_A,[
            { start => '~2015-06-05 13:00:00', stop => '~2015-06-21 13:00:00', cash => 0, profile => $profile_base_y->{id} },
            { start => '~2015-06-21 13:00:00', stop => '~2015-07-21 13:00:00', cash => 8, profile => $profile_silver_y->{id} },
            { start => '~2015-07-21 13:00:00', stop => '~2015-08-21 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
            { start => '~2015-08-21 13:00:00', stop => '~2015-09-21 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
            { start => '~2015-09-21 13:00:00', stop => '~2015-10-21 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
        ]);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-05 13:00:00'));
        my $customer_B = _create_customer($base_package,'B');
        my $subscriber_B = _create_subscriber($customer_B,'of customer B');
        my $v_silver_2 = _create_voucher(10,'SILVER_2_'.$t,undef,$silver_package);
        my $v_extension_1 = _create_voucher(2,'EXTENSION_1_'.$t,undef,$extension_package);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-27 13:00:00'));

        _perform_topup_voucher($subscriber_B,$v_silver_2);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-27 12:00:00'));

        _perform_topup_voucher($subscriber_B,$v_extension_1);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-10-01 13:00:00'));

        _check_interval_history($customer_B,[
            { start => '~2015-06-05 13:00:00', stop => '~2015-06-27 13:00:00', cash => 0, profile => $profile_base_y->{id} },
            { start => '~2015-06-27 13:00:00', stop => '~2015-07-27 13:00:00', cash => 8, profile => $profile_silver_y->{id} },
            { start => '~2015-07-27 13:00:00', stop => '~2015-08-27 13:00:00', cash => 8, profile => $profile_silver_y->{id} },
            { start => '~2015-08-27 13:00:00', stop => '~2015-09-27 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
            { start => '~2015-09-27 13:00:00', stop => '~2015-10-27 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
        ]);


        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-05 13:00:00'));
        my $customer_C = _create_customer($base_package,'C');
        my $subscriber_C = _create_subscriber($customer_C,'of customer C');
        my $v_gold_1 = _create_voucher(20,'GOLD_1_'.$t,undef,$gold_package);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-07-02 13:00:00'));

        _perform_topup_voucher($subscriber_C,$v_gold_1);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-10-01 13:00:00'));

        _perform_topup_cash($subscriber_C,10,$silver_package);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-11-01 13:00:00'));

        _check_interval_history($customer_C,[
            { start => '~2015-06-05 13:00:00', stop => '~2015-07-02 13:00:00', cash => 0, profile => $profile_base_y->{id} },
            { start => '~2015-07-02 13:00:00', stop => '~2015-08-02 13:00:00', cash => 15, profile => $profile_gold_y->{id} },
            { start => '~2015-08-02 13:00:00', stop => '~2015-09-02 13:00:00', cash => 15, profile => $profile_gold_y->{id} },
            { start => '~2015-09-02 13:00:00', stop => '~2015-10-02 13:00:00', cash => 23, profile => $profile_gold_y->{id} },
            { start => '~2015-10-02 13:00:00', stop => '~2015-11-02 13:00:00', cash => 0, profile => $profile_silver_y->{id} },
        ]);

        _set_time();
        #print _stop_recording();
    }

    my $prof_package_create30d = _create_profile_package('create','day',30);
    my $prof_package_1st30d = _create_profile_package('1st','day',30);

    my $prof_package_create1m = _create_profile_package('create','month',1);
    my $prof_package_1st1m = _create_profile_package('1st','month',1);

    my $prof_package_create2w = _create_profile_package('create','week',2);
    my $prof_package_1st2w = _create_profile_package('1st','week',2);

    my $prof_package_topup = _create_profile_package('topup',"month",1);

    my $prof_package_topup_interval = _create_profile_package('topup_interval',"month",1);

    {

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2014-12-30 13:00:00'));

        my $customer_topup = _create_customer($prof_package_topup); #create closest to now
        my $customer_wo = _create_customer();
        my $customer_create1m = _create_customer($prof_package_create1m);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-04-02 02:00:00'));

        _check_interval_history($customer_topup,[
            { start => '~2014-12-30 13:00:00', stop => $infinite_future},
        ]);

        _check_interval_history($customer_wo,[
            { start => '2014-12-01 00:00:00', stop => '2014-12-31 23:59:59'},
            { start => '2015-01-01 00:00:00', stop => '2015-01-31 23:59:59'},
            { start => '2015-02-01 00:00:00', stop => '2015-02-28 23:59:59'},
            { start => '2015-03-01 00:00:00', stop => '2015-03-31 23:59:59'},
            { start => '2015-04-01 00:00:00', stop => '2015-04-30 23:59:59'},
        ]); #,NGCP::Panel::Utils::DateTime::from_string('2014-11-29 13:00:00'));

        _check_interval_history($customer_create1m,[
            { start => '2014-12-30 00:00:00', stop => '2015-01-29 23:59:59'},
            { start => '2015-01-30 00:00:00', stop => '2015-02-27 23:59:59'},
            { start => '2015-02-28 00:00:00', stop => '2015-03-29 23:59:59'},
            { start => '2015-03-30 00:00:00', stop => '2015-04-29 23:59:59'},
        ]);

        _set_time();
    }

    {
        my $ts = '2014-01-07 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $gantt_events = [];

        my $cnt = 1;
        $req_identifier = $cnt . '. create customer'; diag($req_identifier); $cnt++;
        my $customer = _create_customer();
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef },
        ]);

        $ts = '2014-03-01 13:00:00'; $gantt_events = [];
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef },
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef },
            { start => '2014-03-01 00:00:00', stop => '2014-03-31 23:59:59', package_id => undef },
        ]);

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_create30d->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_create30d);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef },
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef },
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ] },
        ]);

        $ts = '2014-04-01 13:00:00';
        $gantt_events = [];
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef },
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef },
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ] },
            { start => '2014-03-07 00:00:00', stop => '2014-04-05 23:59:59', package_id => $prof_package_create30d->{id} },
        ]);

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_1st30d->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_1st30d);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ] },
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59', package_id => [ $prof_package_create30d->{id}, $prof_package_1st30d->{id} ] },
        ]);

        $ts = '2014-05-13 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ]},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59', package_id => [ $prof_package_create30d->{id}, $prof_package_1st30d->{id} ]},
            { start => '2014-05-01 00:00:00', stop => '2014-05-30 23:59:59', package_id => $prof_package_1st30d->{id} },
        ]);

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_create1m->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_create1m);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ]},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59', package_id => [ $prof_package_create30d->{id}, $prof_package_1st30d->{id} ]},
            { start => '2014-05-01 00:00:00', stop => '2014-06-06 23:59:59', package_id => [ $prof_package_1st30d->{id}, $prof_package_create1m->{id} ]},
        ]);

        $ts = '2014-05-27 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ]},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59', package_id => [ $prof_package_create30d->{id}, $prof_package_1st30d->{id} ]},
            { start => '2014-05-01 00:00:00', stop => '2014-06-06 23:59:59', package_id => [ $prof_package_1st30d->{id}, $prof_package_create1m->{id} ]},
        ]);

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_1st1m->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_1st1m);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-01-01 00:00:00', stop => '2014-01-31 23:59:59', package_id => undef},
            { start => '2014-02-01 00:00:00', stop => '2014-02-28 23:59:59', package_id => undef},
            { start => '2014-03-01 00:00:00', stop => '2014-03-06 23:59:59', package_id => [ undef , $prof_package_create30d->{id} ]},
            { start => '2014-03-07 00:00:00', stop => '2014-04-30 23:59:59', package_id => [ $prof_package_create30d->{id}, $prof_package_1st30d->{id} ]},
            { start => '2014-05-01 00:00:00', stop => '2014-05-31 23:59:59', package_id => [ $prof_package_create30d->{id}, $prof_package_1st30d->{id}, $prof_package_1st1m->{id} ]},
        ]);

        my $t1 = $ts;
        $gantt_events = [];
        $ts = '2014-08-03 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_create2w->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_create2w);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-06-01 00:00:00', stop => '2014-06-30 23:59:59', package_id => $prof_package_1st1m->{id}},
            { start => '2014-07-01 00:00:00', stop => '2014-07-31 23:59:59', package_id => $prof_package_1st1m->{id}},
            { start => '2014-08-01 00:00:00', stop => '2014-08-06 23:59:59', package_id => [ $prof_package_1st1m->{id}, $prof_package_create2w->{id} ]},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $t1 = $ts;
        $gantt_events = [];
        $ts = '2014-09-03 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_1st2w->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_1st2w);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-08-07 00:00:00', stop => '2014-08-20 23:59:59', package_id => $prof_package_create2w->{id}},
            { start => '2014-08-21 00:00:00', stop => '2014-09-30 23:59:59', package_id => [ $prof_package_create2w->{id}, $prof_package_1st2w->{id} ]},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        #$t1 = $ts;
        #$ts = '2014-09-03 13:00:00';
        #_set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to no package'; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-08-07 00:00:00', stop => '2014-08-20 23:59:59', package_id => $prof_package_create2w->{id}},
            { start => '2014-08-21 00:00:00', stop => '2014-09-30 23:59:59', package_id => [ $prof_package_create2w->{id}, $prof_package_1st2w->{id}, undef ]},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $t1 = $ts;
        $gantt_events = [];
        #my $t1 = '2014-09-03 13:00:00';
        $ts = '2014-10-04 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_topup->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_topup);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });
        #diag("wait a second here");
        #sleep(1); #sigh
        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-10-01 00:00:00', stop => '~2014-10-04 13:00:00', package_id => undef },
            { start => '~2014-10-04 13:00:00', stop => $infinite_future, package_id => $prof_package_topup->{id}},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $req_identifier = $cnt . '. create topup_start_mode_test1 voucher'; diag($req_identifier); $cnt++;
        my $voucher1 = _create_voucher(10,'topup_start_mode_test1'.$t,$customer);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });
        $req_identifier = $cnt . '. create topup_start_mode_test2 voucher'; diag($req_identifier); $cnt++;
        my $voucher2 = _create_voucher(10,'topup_start_mode_test2'.$t,$customer,$prof_package_create1m);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });
        $req_identifier = $cnt . '. create subscriber for customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        my $subscriber = _create_subscriber($customer);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $t1 = $ts;
        $ts = '2014-10-23 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '~2014-10-04 13:00:00', stop => $infinite_future, package_id => $prof_package_topup->{id}},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $req_identifier = $cnt . '. perform topup with voucher ' . $voucher1->{code}; diag($req_identifier); $cnt++;
        _perform_topup_voucher($subscriber,$voucher1);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
           { start => '~2014-10-04 13:00:00', stop => '~2014-10-23 13:00:00', package_id => $prof_package_topup->{id}},
            { start => '~2014-10-23 13:00:00', stop => $infinite_future, package_id => $voucher1->{package_id}},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $t1 = $ts;
        $gantt_events = [];
        $ts = '2014-11-29 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '~2014-10-23 13:00:00', stop => $infinite_future, package_id => $voucher1->{package_id}},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $req_identifier = $cnt . '. perform topup with voucher ' . $voucher2->{code}; diag($req_identifier); $cnt++;
        _perform_topup_voucher($subscriber,$voucher2);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '~2014-10-23 13:00:00', stop => '2014-12-06 23:59:59', package_id => [$voucher1->{package_id}, $voucher2->{package_id}]},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to no package'; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '~2014-10-23 13:00:00', stop => '2014-11-30 23:59:59', cash => 20, package_id => [$voucher1->{package_id}, $voucher2->{package_id}, undef]},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $t1 = $ts;
        $gantt_events = [];
        $ts = '2015-01-19 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-12-01 00:00:00', stop => '2014-12-31 23:59:59', package_id => undef},
            { start => '2015-01-01 00:00:00', stop => '2015-01-31 23:59:59', package_id => undef},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $req_identifier = $cnt . '. switch customer ' . $customer->{id} . ' to package ' . $prof_package_topup_interval->{description}; diag($req_identifier); $cnt++;
        $customer = _switch_package($customer,$prof_package_topup_interval);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        _check_interval_history($customer,[
            { start => '2014-12-01 00:00:00', stop => '2014-12-31 23:59:59', package_id => undef},
            { start => '2015-01-01 00:00:00', stop => $infinite_future, package_id => [ undef, $prof_package_topup_interval->{id}]},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $req_identifier = $cnt . '. create topup_interval_start_mode_test voucher'; diag($req_identifier); $cnt++;
        my $voucher3 = _create_voucher(15,'topup_interval_start_mode_test'.$t,$customer,$prof_package_topup_interval);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $ts = '2015-03-11 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        $req_identifier = $cnt . '. perform topup with voucher ' . $voucher3->{code}; diag($req_identifier); $cnt++;
        _perform_topup_voucher($subscriber,$voucher3);
        push(@$gantt_events,{ name => $req_identifier, t => $ts });

        $req_identifier = $cnt . '. get balance history of customer ' . $customer->{id}; diag($req_identifier); $cnt++;
        _check_interval_history($customer,[
            { start => '2014-12-01 00:00:00', stop => '2014-12-31 23:59:59', package_id => undef},
            { start => '2015-01-01 00:00:00', stop => '~2015-03-11 13:00:00', package_id => [ undef, $prof_package_topup_interval->{id}]},
            { start => '~2015-03-11 13:00:00', stop => '~2015-04-11 13:00:00', package_id => $prof_package_topup_interval->{id}},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        $ts = '2015-05-17 13:00:00';
        _set_time(NGCP::Panel::Utils::DateTime::from_string($ts));

        _check_interval_history($customer,[
            { start => '2014-12-01 00:00:00', stop => '2014-12-31 23:59:59', package_id => undef},
            { start => '2015-01-01 00:00:00', stop => '~2015-03-11 13:00:00', package_id => [ undef, $prof_package_topup_interval->{id}]},
            { start => '~2015-03-11 13:00:00', stop => '~2015-04-11 13:00:00', package_id => $prof_package_topup_interval->{id}},
            { start => '~2015-04-11 13:00:00', stop => '~2015-05-11 13:00:00', package_id => $prof_package_topup_interval->{id}},
            { start => '~2015-05-11 13:00:00', stop => '~2015-06-11 13:00:00', cash => 35, package_id => $prof_package_topup_interval->{id}},
        ],NGCP::Panel::Utils::DateTime::from_string($t1));

        _set_time();
        undef $req_identifier;
        undef $gantt_events;
    }

    #SKIP:
    {

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-30 13:00:00'));

        my $profile_underrun = _create_billing_profile('UNDERRUN_NOTOPUP');
        my $profile_topup = _create_billing_profile('TOPUP_NOTOPUP');
        my $package = _create_profile_package('create','month',1, notopup_discard_intervals => 2,
            initial_balance => 0, carry_over_mode => 'carry_over',
            topup_profiles => [{ profile_id => $profile_topup->{id}, }, ],
            underrun_profile_threshold => 1, underrun_profiles => [{ profile_id => $profile_underrun->{id}, }, ],);
        my $customer = _create_customer($package);
        my $subscriber = _create_subscriber($customer);
        my $v_notopup = _create_voucher(10,'notopup'.$t);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-02-17 13:00:00'));

        _perform_topup_voucher($subscriber,$v_notopup);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-01 13:00:00'));

        _check_interval_history($customer,[
            { start => '2015-01-30 00:00:00', stop => '2015-02-27 23:59:59', cash => 10, topups => 1, profile => $profile_underrun->{id} }, #topup
            { start => '2015-02-28 00:00:00', stop => '2015-03-29 23:59:59', cash => 10, topups => 0, profile => $profile_topup->{id} },
            { start => '2015-03-30 00:00:00', stop => '2015-04-29 23:59:59', cash => 10, topups => 0, profile => $profile_topup->{id} },
            { start => '2015-04-30 00:00:00', stop => '2015-05-29 23:59:59', cash => 0, topups => 0, profile => $profile_underrun->{id} }, #'notopup_discard_expiry' => '2015-04-30 00:00:00'
            { start => '2015-05-30 00:00:00', stop => '2015-06-29 23:59:59', cash => 0, topups => 0, profile => $profile_underrun->{id} },
            #{ start => '2015-06-30 00:00:00', stop => '2015-07-29 23:59:59', cash => 0, topups => 0 },
        ]);

        _set_time();
    }

    {

        my $profile_underrun = _create_billing_profile('UNDERRUN_NOTOPUP_INF');
        my $profile_initial = _create_billing_profile('INITIAL_NOTOPUP_INF');
        my $package = _create_profile_package('topup_interval','month',1, notopup_discard_intervals => 3,
            initial_balance => 1, carry_over_mode => 'carry_over',
            initial_profiles => [{ profile_id => $profile_initial->{id}, }, ],
            underrun_lock_threshold => 1,
            underrun_lock_level => 4,
            underrun_profile_threshold => 1, underrun_profiles => [{ profile_id => $profile_underrun->{id}, }, ],);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-30 13:00:00'));
        my $customer = _create_customer($package);
        my $subscriber = _create_subscriber($customer);
        #my $v_notopup = _create_voucher(10,'notopup'.$t);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-02-17 13:00:00'));

        #_perform_topup_voucher($subscriber,$v_notopup);
       _check_interval_history($customer,[
            { start => '~2015-01-30 13:00:00', stop => $infinite_future, cash => 0.01, profile => $profile_initial->{id} },
        ]);
        is(_get_customer($customer)->{billing_profile_id},$profile_initial->{id},'check customer actual billing profile id');
        is(_get_subscriber_lock_level($subscriber),undef,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-01 13:00:00'));

       _check_interval_history($customer,[
            { start => '~2015-01-30 13:00:00', stop => $infinite_future, cash => 0.00, profile => $profile_initial->{id} },
        ]);
       is(_get_customer($customer)->{billing_profile_id},$profile_underrun->{id},'check customer actual billing profile id');
       is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time();
    }

    #SKIP:
    {

        my $profile_underrun = _create_billing_profile('UNDERRUN_NOTOPUP_TIM');
        my $profile_initial = _create_billing_profile('INITIAL_NOTOPUP_TIM');
        my $package = _create_profile_package('topup_interval','month',1,
            initial_balance => 1, carry_over_mode => 'carry_over_timely',
            initial_profiles => [{ profile_id => $profile_initial->{id}, }, ],
            timely_duration_unit => 'month',
            timely_duration_value => 1,
            underrun_lock_threshold => 1,
            underrun_lock_level => 4,
            underrun_profile_threshold => 1, underrun_profiles => [{ profile_id => $profile_underrun->{id}, }, ],);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-01-30 13:00:00'));
        my $customer = _create_customer($package);
        my $subscriber = _create_subscriber($customer);
        #my $v_notopup = _create_voucher(10,'notopup'.$t);

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-02-17 13:00:00'));

        #_perform_topup_voucher($subscriber,$v_notopup);
       _check_interval_history($customer,[
            { start => '~2015-01-30 13:00:00', stop => $infinite_future, cash => 0.01, profile => $profile_initial->{id} },
        ]);
        is(_get_customer($customer)->{billing_profile_id},$profile_initial->{id},'check customer actual billing profile id');
        is(_get_subscriber_lock_level($subscriber),undef,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-03-01 13:00:00'));

       _check_interval_history($customer,[
            { start => '~2015-01-30 13:00:00', stop => $infinite_future, cash => 0.00, profile => $profile_initial->{id} },
        ]);
       is(_get_customer($customer)->{billing_profile_id},$profile_underrun->{id},'check customer actual billing profile id');
       is(_get_subscriber_lock_level($subscriber),4,"check subscriber id " . $subscriber->{id} . " lock level");

        _set_time();
    }

    THREADED:
    {
        my $package = _create_profile_package('topup','month',1,
                carry_over_mode => 'carry_over',
                );

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-08-21 13:00:00'));

        my $customer = _create_customer($package,'multi_topup');
        my $subscriber_1 = _create_subscriber($customer,'of customer multi_topup');
        my $subscriber_2 = _create_subscriber($customer,'of customer multi_topup');
        my $subscriber_3 = _create_subscriber($customer,'of customer multi_topup');

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-08-22 13:00:00'));
        my $delay = 5; #try 0 to provoke the concurrent action error
        my $t_a = threads->create(sub { _perform_topup_cash($subscriber_1,2); });
        sleep($delay);
        my $t_b = threads->create(sub { _perform_topup_cash($subscriber_2,2); });
        sleep($delay);
        my $t_c = threads->create(sub { _perform_topup_cash($subscriber_3,2); });
        $t_a->join();
        $t_b->join();
        $t_c->join();


        _check_interval_history($customer,[
            { start => '~2015-08-21 13:00:00', stop => '~2015-08-22 13:00:00', cash => 0, topups => 1 },
            { start => '~2015-08-22 13:00:01', stop => '~2015-08-22 13:00:01', cash => 2, topups => 1 },
            { start => '~2015-08-22 13:00:02', stop => '~2015-08-22 13:00:02', cash => 4, topups => 1 },
            { start => '~2015-08-22 13:00:03', stop => $infinite_future, cash => 6, topups => 0 },
            ]);

        _set_time();
    }

    if (_get_allow_delay_commit()) {
        my $custcontact1 = _create_customer_contact();
        my $custcontact2 = _create_customer_contact();
        _set_time(NGCP::Panel::Utils::DateTime::current_local->subtract(months => 3));
        _create_customers_threaded(3,undef,undef,$custcontact1);
        _create_customers_threaded(3,undef,undef,$custcontact2);
        _set_time();

        my $t1 = time;
        my $delay = 5; #15;

        my $t_a = threads->create(\&_fetch_customerbalances_worker,$delay,'id','asc',$custcontact2);
        my $t_b = threads->create(\&_fetch_customerbalances_worker,$delay,'id','desc',$custcontact2);
        #my $t_c = threads->create(\&_fetch_customerbalances_worker,$delay,'id','asc',$custcontact9);
        my $intervals_a = $t_a->join();
        my $intervals_b = $t_b->join();
        #my $intervals_c = $t_c->join();
        my $t2 = time;
        #my $got_a = [ sort { $a->{id} <=> $b->{id} } @{ $intervals_b->{_embedded}->{'ngcp:balanceintervals'} } ]; #$a->{contract_id}
        is($intervals_a->{total_count},3,"check total count of thread a results");
        is($intervals_b->{total_count},3,"check total count of thread b results");
        #is($intervals_c->{total_count},scalar (grep { $_->{contact_id} == $custcontact9->{id} } values %customer_map),"check total count of thread c results");
        my $got_asc = $intervals_a->{_embedded}->{'ngcp:customerbalances'};
        my $got_desc = $intervals_b->{_embedded}->{'ngcp:customerbalances'};
        if (!is_deeply($got_desc,[ reverse @{ $got_asc } ],'compare customerbalances collection results of threaded requests deeply')) {
             diag(Dumper({asc => $got_asc, desc => $got_desc}));
        }
        my $delta_serialized = $t2 - $t1;
        ok($delta_serialized >= 2*$delay,'expected delay to assume customerbalances requests were processed after another');
        #ok($t2 - $t1 < 3*$delay,'expected delay to assume only required contracts were locked');

        $t1 = time;
        $t_a = threads->create(\&_fetch_customerbalances_worker,$delay,'id','asc',$custcontact1);
        $t_b = threads->create(\&_fetch_customerbalances_worker,$delay,'id','desc',$custcontact2);
        #$t_c = threads->create(\&_fetch_customerbalances_worker,$delay,'id','asc',$custcontact2);
        $intervals_a = $t_a->join();
        $intervals_b = $t_b->join();
        #$intervals_c = $t_c->join();
        $t2 = time;

        is($intervals_a->{total_count},3,"check total count of thread a results");
        is($intervals_b->{total_count},3,"check total count of thread b results");
        #is($intervals_b->{total_count},scalar (grep { $_->{contact_id} == $custcontact9->{id} } values %customer_map),"check total count of thread b results");
        #is($intervals_c->{total_count},3,"check total count of thread c results");

        ok($t2 - $t1 < $delta_serialized,'expected delay to assume only required contracts were locked and requests were performed in parallel') if !$disable_parallel_catchup;

    } else {
        diag('allow_delay_commit not set, skipping ...');
    }

    if (_get_allow_delay_commit()) {
        my $custcontact1 = _create_customer_contact();
        my $custcontact2 = _create_customer_contact();
        _set_time(NGCP::Panel::Utils::DateTime::current_local->subtract(months => 3));
        _create_customers_threaded(3,undef,undef,$custcontact1);
        _create_customers_threaded(3,undef,undef,$custcontact2);
        _set_time();

        my $t1 = time;
        my $delay = 5; #15;

        my $t_a = threads->create(\&_fetch_intervals_worker,$delay,'id','asc',$custcontact2);
        my $t_b = threads->create(\&_fetch_intervals_worker,$delay,'id','desc',$custcontact2);
        #my $t_c = threads->create(\&_fetch_intervals_worker,$delay,'id','desc',$custcontact9);
        my $intervals_a = $t_a->join();
        my $intervals_b = $t_b->join();
        #my $intervals_c = $t_c->join();
        my $t2 = time;
        is($intervals_a->{total_count},3,"check total count of thread a results");
        is($intervals_b->{total_count},3,"check total count of thread b results");
        #is($intervals_c->{total_count},scalar (grep { $_->{contact_id} == $custcontact9->{id} } values %customer_map),"check total count of thread c results");
        #my $got_a = [ sort { $a->{id} <=> $b->{id} } @{ $intervals_b->{_embedded}->{'ngcp:balanceintervals'} } ]; #$a->{contract_id}
        my $got_asc = $intervals_a->{_embedded}->{'ngcp:balanceintervals'};
        my $got_desc = $intervals_b->{_embedded}->{'ngcp:balanceintervals'};
        if (!is_deeply($got_desc,[ reverse @{ $got_asc } ],'compare interval collection results of threaded requests deeply')) {
             diag(Dumper({asc => $got_asc, desc => $got_desc}));
        }
        my $delta_serialized = $t2 - $t1;
        ok($delta_serialized >= 2*$delay,'expected delay to assume balanceintervals requests were processed after another');
        #ok($t2 - $t1 < 3*$delay,'expected delay to assume only required contracts were locked');

        $t1 = time;
        $t_a = threads->create(\&_fetch_intervals_worker,$delay,'id','asc',$custcontact1);
        $t_b = threads->create(\&_fetch_intervals_worker,$delay,'id','desc',$custcontact2);
        #$t_c = threads->create(\&_fetch_intervals_worker,$delay,'id','desc',$custcontact3);
        $intervals_a = $t_a->join();
        $intervals_b = $t_b->join();
        #$intervals_c = $t_c->join();
        $t2 = time;

        is($intervals_a->{total_count},3,"check total count of thread a results");
        is($intervals_b->{total_count},3,"check total count of thread b results");
        #is($intervals_b->{total_count},scalar (grep { $_->{contact_id} == $custcontact9->{id} } values %customer_map),"check total count of thread b results");
        #is($intervals_c->{total_count},3,"check total count of thread c results");

        ok($t2 - $t1 < $delta_serialized,'expected delay to assume only required contracts were locked and requests were perfomed in parallel') if !$disable_parallel_catchup;


    } else {
        diag('allow_delay_commit not set, skipping ...');
    }

    if (_get_allow_delay_commit()) {
        my $custcontact1 = _create_customer_contact();
        my $custcontact2 = _create_customer_contact();
        my $package = _create_profile_package('create','month',1,initial_balance => 1, carry_over_mode => 'discard', underrun_lock_threshold => 1, underrun_lock_level => 4);
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-05-17 13:00:00'));
        _create_customers_threaded(3,2,$package,$custcontact1);
        _create_customers_threaded(3,2,$package,$custcontact2);

        my $t1 = time;
        my $delay = 5.0; #15.0; #10.0; #2.0;
        my $t_a = threads->create(\&_fetch_preferences_worker,$delay,'id','asc',$custcontact2);
        my $t_b = threads->create(\&_fetch_preferences_worker,$delay,'id','desc',$custcontact2);
        #my $t_c = threads->create(\&_fetch_preferences_worker,$delay,'id','desc',$custcontact9);
        my $prefs_a = $t_a->join();
        my $prefs_b = $t_b->join();
        #my $prefs_c = $t_c->join();
        my $t2 = time;
        is($prefs_a->{total_count},2*3,"check total count of thread a results");
        is($prefs_b->{total_count},2*3,"check total count of thread b results");
        #is($prefs_c->{total_count},scalar (grep { $customer_map{$_->{customer_id}}->{contact_id} == $custcontact9->{id} } values %subscriber_map),"check total count of thread c results");
        my $got_asc = $prefs_a->{_embedded}->{'ngcp:subscriberpreferences'};
        my $got_desc = $prefs_b->{_embedded}->{'ngcp:subscriberpreferences'};
        if (!is_deeply($got_desc,[ reverse @{ $got_asc } ],'compare subscriber preference collection results of threaded requests deeply')) {
             diag(Dumper({asc => $got_asc, desc => $got_desc}));
        }
        my $delta_serialized = $t2 - $t1;
        ok($delta_serialized >= 2*$delay,'expected delay to assume subscriberpreferences requests were processed after another');
        #ok($t2 - $t1 < 3*$delay,'expected delay to assume only required contracts were locked');
        for (my $i = 0; $i < 2*3; $i++) {
            is($got_desc->[$i]->{lock},undef,"check if subscriber is unlocked initially");
        }

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-18 13:00:00'));

        #$t1 = time;

        #$t_a = threads->create(\&_fetch_preferences_worker,$delay,'id','asc',$custcontact4);
        #$t_b = threads->create(\&_fetch_preferences_worker,$delay,'id','desc',$custcontact9);
        ##$t_c = threads->create(\&_fetch_preferences_worker,$delay,'id','desc',$custcontact9);
        #$prefs_a = $t_a->join();
        #$prefs_b = $t_b->join();
        ##$prefs_c = $t_c->join();
        #$t2 = time;
        #is($prefs_a->{total_count},2*3,"check total count of thread a results");
        ##is($prefs_b->{total_count},2*3,"check total count of thread b results");
        #is($prefs_b->{total_count},scalar (grep { $customer_map{$_->{customer_id}}->{contact_id} == $custcontact9->{id} } values %subscriber_map),"check total count of thread b results");
        #$got_asc = $prefs_a->{_embedded}->{'ngcp:subscriberpreferences'};
        #$got_desc = $prefs_b->{_embedded}->{'ngcp:subscriberpreferences'};
        #if (!is_deeply($got_desc,[ reverse @{ $got_asc } ],'compare subscriber preference collection results of threaded requests deeply')) {
        #     diag(Dumper({asc => $got_asc, desc => $got_desc}));
        #}
        #ok($t2 - $t1 > 2*$delay,'expected delay to assume subscriberpreferences requests were processed after another');
        #ok($t2 - $t1 < 3*$delay,'expected delay to assume only required contracts were locked');
        #for (my $i = 0; $i < 2*3; $i++) {
        #    is($got_desc->[$i]->{lock},4,"check if subscriber is locked now");
        #}

        $t1 = time;
        $t_a = threads->create(\&_fetch_preferences_worker,$delay,'id','asc',$custcontact1);
        $t_b = threads->create(\&_fetch_preferences_worker,$delay,'id','desc',$custcontact2);
        #$t_c = threads->create(\&_fetch_preferences_worker,$delay,'id','desc',$custcontact4);
        $prefs_a = $t_a->join();
        $prefs_b = $t_b->join();
        #$prefs_c = $t_c->join();
        $t2 = time;

        is($prefs_a->{total_count},2*3,"check total count of thread a results");
        is($prefs_b->{total_count},2*3,"check total count of thread b results");
        #is($prefs_b->{total_count},scalar (grep { $customer_map{$_->{customer_id}}->{contact_id} == $custcontact9->{id} } values %subscriber_map),"check total count of thread b results");
        #is($prefs_c->{total_count},2*3,"check total count of thread c results");
        $got_asc = $prefs_a->{_embedded}->{'ngcp:subscriberpreferences'};
        for (my $i = 0; $i < 2*3; $i++) {
            is($got_asc->[$i]->{lock},4,"check if subscriber is locked now");
        }

        ok($t2 - $t1 < $delta_serialized,'expected delay to assume only required contracts were locked and requests were performed in parallel') if !$disable_parallel_catchup;

        $t1 = time;
        $t_a = threads->create(\&_fetch_preferences_worker,$delay,'id','asc',$custcontact2);
        sleep($delay/2.0);
        my $last_customer_id = shift(@{[sort {$b <=> $a} keys %customer_map]});
        _check_interval_history($customer_map{$last_customer_id},[
            { start => '2015-05-17 00:00:00', stop => '2015-06-16 23:59:59', cash => 0.01, package_id => $package->{id}, profile => $billingprofile->{id} },
            { start => '2015-06-17 00:00:00', stop => '2015-07-16 23:59:59', cash => 0, package_id => $package->{id}, profile => $billingprofile->{id} },
            ]);
        $t2 = time;
        $t_a->join();

        ok($t2 - $t1 >= $delay,'expected delay to assume subscriberpreferences request locks contracts and an simultaneous access to contract id ' . $last_customer_id . ' is serialized');

        _set_time();

    } else {
        diag('allow_delay_commit not set, skipping ...');
    }

    if (_get_allow_delay_commit()) {
        my $custcontact1 = _create_customer_contact();
        my $custcontact2 = _create_customer_contact();
        my $package = _create_profile_package('create','month',1,initial_balance => 1, carry_over_mode => 'discard', underrun_lock_threshold => 1, underrun_lock_level => 4);
        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-05-17 13:00:00'));
        _create_customers_threaded(3,2,$package,$custcontact1);
        _create_customers_threaded(3,2,$package,$custcontact2);

        my $t1 = time;
        my $delay = 5.0; #15.0; #10.0; #2.0;
        my $t_a = threads->create(\&_fetch_subscribers_worker,$delay,'id','asc',$custcontact2);
        my $t_b = threads->create(\&_fetch_subscribers_worker,$delay,'id','desc',$custcontact2);
        #my $t_c = threads->create(\&_fetch_subscribers_worker,$delay,'id','desc',$custcontact9);
        my $subs_a = $t_a->join();
        my $subs_b = $t_b->join();
        #my $subs_c = $t_c->join();
        my $t2 = time;
        is($subs_a->{total_count},2*3,"check total count of thread a results");
        is($subs_b->{total_count},2*3,"check total count of thread b results");
        #is($subs_c->{total_count},scalar (grep { $customer_map{$_->{customer_id}}->{contact_id} == $custcontact9->{id} } values %subscriber_map),"check total count of thread c results");
        my $got_asc = $subs_a->{_embedded}->{'ngcp:subscribers'};
        my $got_desc = $subs_b->{_embedded}->{'ngcp:subscribers'};
        if (!is_deeply($got_desc,[ reverse @{ $got_asc } ],'compare subscriber collection results of threaded requests deeply')) {
             diag(Dumper({asc => $got_asc, desc => $got_desc}));
        }
        my $delta_serialized = $t2 - $t1;
        ok($delta_serialized >= 2*$delay,'expected delay to assume subscribers requests were processed after another');
        #ok($t2 - $t1 < 3*$delay,'expected delay to assume only required contracts were locked');
        for (my $i = 0; $i < 2*3; $i++) {
            is($got_desc->[$i]->{lock},undef,"check if subscriber is unlocked initially");
        }

        _set_time(NGCP::Panel::Utils::DateTime::from_string('2015-06-18 13:00:00'));

        #$t1 = time;
        #
        #$t_a = threads->create(\&_fetch_subscribers_worker,$delay,'id','asc',$custcontact5);
        #$t_b = threads->create(\&_fetch_subscribers_worker,$delay,'id','desc',$custcontact9);
        ##$t_c = threads->create(\&_fetch_subscribers_worker,$delay,'id','desc',$custcontact9);
        #$subs_a = $t_a->join();
        #$subs_b = $t_b->join();
        ##$subs_c = $t_c->join();
        #$t2 = time;
        #is($subs_a->{total_count},2*3,"check total count of thread a results");
        #is($subs_b->{total_count},2*3,"check total count of thread b results");
        #is($subs_c->{total_count},scalar (grep { $customer_map{$_->{customer_id}}->{contact_id} == $custcontact9->{id} } values %subscriber_map),"check total count of thread c results");
        #$got_asc = $subs_a->{_embedded}->{'ngcp:subscribers'};
        #$got_desc = $subs_b->{_embedded}->{'ngcp:subscribers'};
        #if (!is_deeply($got_desc,[ reverse @{ $got_asc } ],'compare subscriber collection results of threaded requests deeply')) {
        #     diag(Dumper({asc => $got_asc, desc => $got_desc}));
        #}
        #ok($t2 - $t1 > 2*$delay,'expected delay to assume subscribers requests were processed after another');
        #ok($t2 - $t1 < 3*$delay,'expected delay to assume only required contracts were locked');
        #for (my $i = 0; $i < 2*3; $i++) {
        #    is($got_desc->[$i]->{lock},4,"check if subscriber is locked now");
        #}

        $t1 = time;
        $t_a = threads->create(\&_fetch_subscribers_worker,$delay,'id','asc',$custcontact1);
        $t_b = threads->create(\&_fetch_subscribers_worker,$delay,'id','desc',$custcontact2);
        #$t_c = threads->create(\&_fetch_subscribers_worker,$delay,'id','desc',$custcontact5);
        $subs_a = $t_a->join();
        $subs_b = $t_b->join();
        #$subs_c = $t_c->join();
        $t2 = time;

        is($subs_a->{total_count},2*3,"check total count of thread a results");
        is($subs_b->{total_count},2*3,"check total count of thread b results");
        #is($subs_b->{total_count},scalar (grep { $customer_map{$_->{customer_id}}->{contact_id} == $custcontact9->{id} } values %subscriber_map),"check total count of thread b results");
        #is($subs_c->{total_count},2*3,"check total count of thread c results");
        $got_asc = $subs_a->{_embedded}->{'ngcp:subscribers'};
        for (my $i = 0; $i < 2*3; $i++) {
            is($got_asc->[$i]->{lock},4,"check if subscriber is locked now");
        }
        ok($t2 - $t1 < $delta_serialized,'expected delay to assume only required contracts were locked and requests were performed in parallel') if !$disable_parallel_catchup;

        $t1 = time;
        $t_a = threads->create(\&_fetch_subscribers_worker,$delay,'id','asc',$custcontact2);
        sleep($delay/2.0);
        my $last_customer_id = shift(@{[sort {$b <=> $a} keys %customer_map]});
        _check_interval_history($customer_map{$last_customer_id},[
            { start => '2015-05-17 00:00:00', stop => '2015-06-16 23:59:59', cash => 0.01, package_id => $package->{id}, profile => $billingprofile->{id} },
            { start => '2015-06-17 00:00:00', stop => '2015-07-16 23:59:59', cash => 0, package_id => $package->{id}, profile => $billingprofile->{id} },
            ]);
        $t2 = time;
        $t_a->join();

        ok($t2 - $t1 >= $delay,'expected delay to assume subscribers request locks contracts and an simultaneous access to contract id ' . $last_customer_id . ' is serialized');

        _set_time();

    } else {
        diag('allow_delay_commit not set, skipping ...');
    }

} else {
    diag('allow_fake_client_time not set, skipping ...');
}

for my $custcontact (values %$customer_contact_map) { #$default_custcontact,$custcontact2,$custcontact3,$custcontact4,$custcontact9) {
    { #test balanceintervals root collection and item
        _create_customers_threaded(3,undef,undef,$custcontact); # unless _get_allow_fake_client_time() && $enable_profile_packages;

        my $total_count = scalar grep { $_->{contact_id} == $custcontact->{id} } values %customer_map; #(scalar keys %customer_map);
        my $nexturi = $uri.'/api/balanceintervals/?page=1&rows=' . ((not defined $total_count or $total_count <= 2) ? 2 : $total_count - 1) . '&contact_id='.$custcontact->{id};
        do {
            $req = HTTP::Request->new('GET',$nexturi);
            $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
            $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
            $res = $ua->request($req);
            #$res = $ua->get($nexturi);
            is($res->code, 200, "balanceintervals root collection: fetch balance intervals collection page");
            my $collection = JSON::from_json($res->decoded_content);
            my $selfuri = $uri . $collection->{_links}->{self}->{href};
            is($selfuri, $nexturi, "balanceintervals root collection: check _links.self.href of collection");
            my $colluri = URI->new($selfuri);

            ok(defined $total_count ? ($collection->{total_count} == $total_count) : ($collection->{total_count} > 0), "balanceintervals root collection: check 'total_count' of collection");

            my %q = $colluri->query_form;
            ok(exists $q{page} && exists $q{rows}, "balanceintervals root collection: check existence of 'page' and 'row' in 'self'");
            my $page = int($q{page});
            my $rows = int($q{rows});
            if($page == 1) {
                ok(!exists $collection->{_links}->{prev}->{href}, "balanceintervals root collection: check absence of 'prev' on first page");
            } else {
                ok(exists $collection->{_links}->{prev}->{href}, "balanceintervals root collection: check existence of 'prev'");
            }
            if(($collection->{total_count} / $rows) <= $page) {
                ok(!exists $collection->{_links}->{next}->{href}, "balanceintervals root collection: check absence of 'next' on last page");
            } else {
                ok(exists $collection->{_links}->{next}->{href}, "balanceintervals root collection: check existence of 'next'");
            }

            if($collection->{_links}->{next}->{href}) {
                $nexturi = $uri . $collection->{_links}->{next}->{href};
            } else {
                $nexturi = undef;
            }

            # TODO: I'd expect that to be an array ref in any case!
            ok(ref $collection->{_links}->{'ngcp:balanceintervals'} eq "ARRAY", "balanceintervals root collection: check if 'ngcp:balanceintervals' is array");

            my $page_items = {};

            foreach my $interval_link (@{ $collection->{_links}->{'ngcp:balanceintervals'} }) {
                #delete $customers{$c->{href}};
                #ok(exists $journals->{$journal->{href}},"check page journal item link");

                $req = HTTP::Request->new('GET',$uri . $interval_link->{href});
                $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
                $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;

                $res = $ua->request($req);
                is($res->code, 200, "balanceintervals root collection: fetch page balance interval item");
                my $interval = JSON::from_json($res->decoded_content);

                $page_items->{$interval->{id}} = $interval;
            }
            foreach my $interval (@{ $collection->{_embedded}->{'ngcp:balanceintervals'} }) {
                ok(exists $page_items->{$interval->{id}},"balanceintervals root collection: check existence of linked item among embedded");
                my $fetched = delete $page_items->{$interval->{id}};
                delete $fetched->{content};
                is_deeply($interval,$fetched,"balanceintervals root collection: compare fetched and embedded item deeply");
            }
            ok((scalar keys %{ $page_items }) == 0,"balanceintervals root collection: check if all embedded items are linked");

        } while($nexturi);

    }
}

done_testing;

sub _check_interval_history {

    my ($customer,$expected_interval_history,$limit_dt,$record_label) = @_;
    my $total_count = (scalar @$expected_interval_history);
    #my @got_interval_history = ();
    my $i = 0;
    my $limit = '';
    my $ok = 1;
    my @intervals;
    $limit = '&start=' . DateTime::Format::ISO8601->parse_datetime($limit_dt) if defined $limit_dt;
    my @requests = ();
    my $last_request;
    $last_request = _req_to_debug($req) if $req;
    my $label = 'interval history of contract with ' . ($customer->{profile_package_id} ? 'package ' . $package_map->{$customer->{profile_package_id}}->{name} : 'no package') . ': ';
    my $nexturi = $uri.'/api/balanceintervals/'.$customer->{id}.'/?page=1&rows=10&order_by_direction=asc&order_by=start'.$limit;
    do {
        $req = HTTP::Request->new('GET',$nexturi);
        $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
        $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
        $res = $ua->request($req);
        #$res = $ua->get($nexturi);
        is($res->code, 200, $label . "fetch balance intervals collection page");
        push(@requests,_req_to_debug($req));
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        #is($selfuri, $nexturi, $label . "check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        $ok = ok($collection->{total_count} == $total_count, $label . "check 'total_count' of collection") && $ok;

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, $label . "check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $collection->{_links}->{prev}->{href}, $label . "check absence of 'prev' on first page");
        } else {
            ok(exists $collection->{_links}->{prev}->{href}, $label . "check existence of 'prev'");
        }
        if(($collection->{total_count} / $rows) <= $page) {
            ok(!exists $collection->{_links}->{next}->{href}, $label . "check absence of 'next' on last page");
        } else {
            ok(exists $collection->{_links}->{next}->{href}, $label . "check existence of 'next'");
        }

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        ok(ref $collection->{_links}->{'ngcp:balanceintervals'} eq "ARRAY", $label . "check if 'ngcp:balanceintervals' is array");

        my $page_items = {};

        #foreach my $interval_link (@{ $collection->{_links}->{'ngcp:balanceintervals'} }) {
        #    #delete $customers{$c->{href}};
        #    #ok(exists $journals->{$journal->{href}},"check page journal item link");
        #
        #    $req = HTTP::Request->new('GET',$uri . $interval_link->{href});
        #    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
        #    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
        #    $res = $ua->request($req);
        #    is($res->code, 200, $label . "fetch page balance interval item");
        #    my $interval = JSON::from_json($res->decoded_content);
        #
        #    $page_items->{$interval->{id}} = $interval;
        #}
        foreach my $interval (@{ $collection->{_embedded}->{'ngcp:balanceintervals'} }) {
            #ok(exists $page_items->{$interval->{id}},$label . "check existence of linked item among embedded");
            #my $fetched = delete $page_items->{$interval->{id}};
            #delete $fetched->{content};
            #is_deeply($interval,$fetched,$label . "compare fetched and embedded item deeply");
            $ok = _compare_interval($interval,$expected_interval_history->[$i],$label) && $ok;
            delete $interval->{'_links'};
            push(@intervals,$interval);
            $i++
        }
        #ok((scalar keys $page_items) == 0,$label . "check if all embedded items are linked");

        _record_request("view contract balances" . ($record_label ? ' of ' . $record_label : ''),$req,undef,$collection);

    } while($nexturi);

    ok($i == $total_count,$label . "check if all expected items are listed");
    _create_gantt($customer,$expected_interval_history);
    diag(Dumper({last_request => $last_request, collection_requests => \@requests, result_intervals => \@intervals})) if !$ok;

}

sub _compare_interval {
    my ($got,$expected,$label) = @_;

    my $ok = 1;
    if ($expected->{start}) {
        #is(NGCP::Panel::Utils::DateTime::from_string($got->{start}),NGCP::Panel::Utils::DateTime::from_string($expected->{start}),$label . "check interval " . $got->{id} . " start timestmp");
        if (substr($expected->{start},0,1) eq '~') {
            $ok = _is_ts_approx($got->{start},$expected->{start},$label . "check interval " . $got->{id} . " start timestamp") && $ok;
        } else {
            $ok = is($got->{start},$expected->{start},$label . "check interval " . $got->{id} . " start timestmp") && $ok;
        }
    }
    if ($expected->{stop}) {
        #is(NGCP::Panel::Utils::DateTime::from_string($got->{stop}),NGCP::Panel::Utils::DateTime::from_string($expected->{stop}),$label . "check interval " . $got->{id} . " stop timestmp");
        if (substr($expected->{stop},0,1) eq '~') {
            $ok = _is_ts_approx($got->{stop},$expected->{stop},$label . "check interval " . $got->{id} . " stop timestamp") && $ok;
        } else {
            $ok = is($got->{stop},$expected->{stop},$label . "check interval " . $got->{id} . " stop timestamp") && $ok;
        }
    }

    if ($expected->{cash}) {
        $ok = is($got->{cash_balance},$expected->{cash},$label . "check interval " . $got->{id} . " cash balance") && $ok;
    }

    if ($expected->{profile}) {
        $ok = is($got->{billing_profile_id},$expected->{profile},$label . "check interval " . $got->{id} . " billing profile") && $ok;
    }

    if ($expected->{topups}) {
        $ok = is($got->{topup_count},$expected->{topups},$label . "check interval " . $got->{id} . " topup count") && $ok;
    }

    if ($expected->{timely_topups}) {
        $ok = is($got->{timely_topup_count},$expected->{timely_topups},$label . "check interval " . $got->{id} . " timely topup count") && $ok;
    }

    return $ok;

}

sub _is_ts_approx {
    my ($got,$expected,$label) = @_;
    $got = NGCP::Panel::Utils::DateTime::from_string($got);
    $expected = NGCP::Panel::Utils::DateTime::from_string(substr($expected,1));
    my $epsilon = 10;
    my $lower = $expected->clone->subtract(seconds => $epsilon);
    my $upper = $expected->clone->add(seconds => $epsilon);
    return ok($got >= $lower && $got <= $upper,$label . ' approximately (' . $got . ')');
}

sub _fetch_intervals_worker {
    my ($delay,$sort_column,$dir,$custcontact) = @_;
    diag("starting thread " . threads->tid() . " ...");
    $req = HTTP::Request->new('GET', $uri.'/api/balanceintervals/?order_by='.$sort_column.'&order_by_direction='.$dir.'&contact_id='.$custcontact->{id}.'&rows='.(scalar keys %customer_map));
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $req->header('X-Delay-Commit' => $delay);
    $res = $ua->request($req);
    is($res->code, 200, "thread " . threads->tid() . ": concurrent fetch balanceintervals of contracts of contact id ".$custcontact->{id} . " in " . $dir . " order");
    my $result = JSON::from_json($res->decoded_content);
    #is($result->{total_count},(scalar keys %customer_map),"check total count");
    diag("finishing thread " . threads->tid() . " ...");
    return $result;
}

sub _fetch_customerbalances_worker {
    my ($delay,$sort_column,$dir,$custcontact) = @_;
    diag("starting thread " . threads->tid() . " ...");
    $req = HTTP::Request->new('GET', $uri.'/api/customerbalances/?order_by='.$sort_column.'&order_by_direction='.$dir.'&contact_id='.$custcontact->{id}.'&rows='.(scalar keys %customer_map));
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $req->header('X-Delay-Commit' => $delay);
    $res = $ua->request($req);
    is($res->code, 200, "thread " . threads->tid() . ": concurrent fetch customerbalances of contracts of contact id ".$custcontact->{id} . " in " . $dir . " order");
    my $result = JSON::from_json($res->decoded_content);
    #is($result->{total_count},(scalar keys %customer_map),"check total count");
    diag("finishing thread " . threads->tid() . " ...");
    return $result;
}

sub _create_customers_threaded {
    my ($number_of_customers,$subscribers_per_customer,$package,$custcontact) = @_;
    my $t0 = time;
    my @t_cs = ();
    #my $number_of_customers = 3;
    for (1..$number_of_customers) {
        my $t_c;
        $t_c = threads->create(sub {
            my $customer = _create_customer($package,undef,$custcontact);
            if (defined $subscribers_per_customer && $subscribers_per_customer > 0) {
                for (1..$subscribers_per_customer) {
                    _create_subscriber($customer);
                }
            }
        });
        push(@t_cs,$t_c);
    }
    foreach my $t_c (@t_cs) {
        $t_c->join();
    }
    my $t1 = time;
    diag('average time to create a customer: ' . ($t1 - $t0)/$number_of_customers);
}

sub _create_customer_contact {

    my $n = (scalar keys %$customer_contact_map);
    $req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $req->content(JSON::to_json({
        firstname => "cust_contact_".$n."_first",
        lastname  => "cust_contact_".$n."_last",
        email     => "cust_contact".$n."\@custcontact.invalid",
        reseller_id => $default_reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create customer contact $n");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch customer contact $n");
    my $custcontact = JSON::from_json($res->decoded_content);
    $customer_contact_map->{$custcontact->{id}} = $custcontact;
    return $custcontact;

}

sub _create_customer {

    my ($package,$record_label,$custcontact) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    my $req_data = {
        status => "active",
        contact_id => (defined $custcontact ? $custcontact->{id} : $default_custcontact->{id}),
        type => "sipaccount",
        ($package ? (billing_profile_definition => 'package',
                     profile_package_id => $package->{id}) :
                     (billing_profile_id => $billingprofile->{id})),
        max_subscribers => undef,
        external_id => undef,
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    my $label = 'test customer ' . ($package ? 'with package ' . $package->{name} : 'w/o profile package');
    is($res->code, 201, "create " . $label);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $res = $ua->request($req);
    is($res->code, 200, "fetch " . $label);
    my $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = threads::shared::shared_clone($customer);
    _record_request("create customer" . ($record_label ? ' ' . $record_label : ''),$request,$req_data,$customer);
    return $customer;

}

sub _get_customer {
    my $customer = shift;
    $req = HTTP::Request->new('GET', $uri.'/api/customers/'.$customer->{id});
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $res = $ua->request($req);
    is($res->code, 200, "fetch customer id " . $customer->{id});
    $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = threads::shared::shared_clone($customer);
    return $customer;
}

sub _switch_package {

    my ($customer,$package) = @_;
    $req = HTTP::Request->new('PATCH', $uri.'/api/customers/'.$customer->{id});
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/profile_package_id', value => ($package ? $package->{id} : undef) } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "patch customer from " . ($customer->{profile_package_id} ? 'package ' . $package_map->{$customer->{profile_package_id}}->{name} : 'no package') . " to " .
       ($package ? $package->{name} : 'no package'));
    $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = threads::shared::shared_clone($customer);
    return $customer;

}

sub _set_time {
    my ($o) = @_;
    my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T',
        );
    if (defined $o) {
        NGCP::Panel::Utils::DateTime::set_fake_time($o);
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        diag("applying fake time offset '$o' - current time: " . $dtf->format_datetime($now));
    } else {
        NGCP::Panel::Utils::DateTime::set_fake_time();
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        diag("resetting fake time - current time: " . $dtf->format_datetime($now));
    }
}

sub _get_fake_clienttime_now {
    #return NGCP::Panel::Utils::DateTime::to_rfc1123_string(NGCP::Panel::Utils::DateTime::current_local);
    #with rfc1123 there could be a problem if jenkins runner and test host will not have the same (language) locale
    return NGCP::Panel::Utils::DateTime::to_string(NGCP::Panel::Utils::DateTime::current_local);
}

sub _create_profile_package {

    my ($start_mode,$interval_unit,$interval_value,@further_opts) = @_; #$notopup_discard_intervals
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    my $name = $start_mode . ($interval_unit ? '/' . $interval_value . ' ' . $interval_unit : '');
    $req->content(JSON::to_json({
        name => "test '" . $name . "' profile package " . (scalar keys %$package_map) . '_' . $t,
        #description  => "test prof package descr " . (scalar keys %$package_map) . '_' . $t,
        description  => $start_mode . "/" . $interval_value . " " . $interval_unit . "s",
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ],
        balance_interval_start_mode => $start_mode,
        ($interval_unit ? (balance_interval_value => $interval_value,
                            balance_interval_unit => $interval_unit,) : ()),
        #notopup_discard_intervals => $notopup_discard_intervals,
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage - '" . $name . "'");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage - '" . $name . "'");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    return $package;

}

sub _create_billing_network_x {

    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "test billing network X ".$t,
        description  => "billing network X descr ".$t,
        reseller_id => $default_reseller_id,
        blocks => [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                   {ip=>'fdfe::5a55:caff:fefa:908a'},
                   {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billingnetwork X");
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billingnetwork X");
    my $network = JSON::from_json($res->decoded_content);
    _record_request("create billing network X",$request,$req_data,$network);
    return $network;
}

sub _create_billing_network_y {

    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "test billing network Y ".$t,
        description  => "billing network Y descr ".$t,
        reseller_id => $default_reseller_id,
        blocks => [{ip=>'10.0.4.7',mask=>26}, #0..63
                      {ip=>'10.0.4.99',mask=>26}, #64..127
                      {ip=>'10.0.5.9',mask=>24},
                        {ip=>'10.0.6.9',mask=>24},],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billingnetwork Y");
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billingnetwork Y");
    my $network = JSON::from_json($res->decoded_content);
    _record_request("create billing network Y",$request,$req_data,$network);
    return $network;
}

sub _create_base_profile_package {

    my ($profile_base_any,$profile_base_x,$profile_base_b,$network_x,$network_b) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "base profile package " . $t,
        description  => "base prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $profile_base_any->{id}, },
                             { profile_id => $profile_base_x->{id}, network_id => $network_x->{id} },
                             { profile_id => $profile_base_b->{id}, network_id => $network_b->{id} }],
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over_timely',
        timely_duration_value => 1,
        timely_duration_unit => 'month',
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test base profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed base profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create BASE profile package",$request,$req_data,$package);
    return $package;

}

sub _create_silver_profile_package {

    my ($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "silver profile package " . $t,
        description  => "silver prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => $base_package->{initial_profiles},
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over_timely',
        timely_duration_value => 1,
        timely_duration_unit => 'month',

        service_charge => 200,
        topup_profiles => [ #{ profile_id => $profile_silver_any->{id}, },
                             { profile_id => $profile_silver_x->{id}, network_id => $network_x->{id} } ,
                             { profile_id => $profile_silver_y->{id}, network_id => $network_y->{id} } ],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test silver profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed silver profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create SILVER profile package",$request,$req_data,$package);
    return $package;

}

sub _create_extension_profile_package {

    my ($base_package,$profile_silver_x,$profile_silver_y,$network_x,$network_y) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "extension profile package " . $t,
        description  => "extension prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => $base_package->{initial_profiles},
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over_timely',
        timely_duration_value => 1,
        timely_duration_unit => 'month',

        service_charge => 200,
        topup_profiles => [ #{ profile_id => $profile_silver_any->{id}, },
                             { profile_id => $profile_silver_x->{id}, network_id => $network_x->{id} } ,
                             { profile_id => $profile_silver_y->{id}, network_id => $network_y->{id} } ],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test extension profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed extension profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create EXTENSION profile package",$request,$req_data,$package);
    return $package;

}

sub _create_gold_profile_package {

    my ($base_package,$profile_gold_x,$profile_gold_y,$network_x,$network_y) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => "gold profile package " . $t,
        description  => "gold prof package descr " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => $base_package->{initial_profiles},
        balance_interval_start_mode => 'topup_interval',
        balance_interval_value => 1,
        balance_interval_unit => 'month',
        carry_over_mode => 'carry_over',
        #timely_duration_value => 1,
        #timely_duration_unit => 'month',

        service_charge => 500,
        topup_profiles => [ #{ profile_id => $profile_gold_any->{id}, },
                             { profile_id => $profile_gold_x->{id}, network_id => $network_x->{id} } ,
                             { profile_id => $profile_gold_y->{id}, network_id => $network_y->{id} } ],
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test gold profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    my $request = $req;
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed gold profilepackage");
    my $package = JSON::from_json($res->decoded_content);
    $package_map->{$package->{id}} = $package;
    _record_request("create GOLD profile package",$request,$req_data,$package);
    return $package;

}

sub _create_voucher {

    my ($amount,$code,$customer,$package,$valid_until_dt) = @_;
    my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T',
        );
    $req = HTTP::Request->new('POST', $uri.'/api/vouchers/');
    $req->header('Content-Type' => 'application/json');
    my $req_data = {
        amount => $amount * 100.0,
        code => $code,
        customer_id => ($customer ? $customer->{id} : undef),
        package_id => ($package ? $package->{id} : undef),
        reseller_id => $default_reseller_id,
        valid_until => $dtf->format_datetime($valid_until_dt ? $valid_until_dt : NGCP::Panel::Utils::DateTime::current_local->add(years => 1)),
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    my $label = 'test voucher (' . ($customer ? 'for customer ' . $customer->{id} : 'no customer') . ', ' . ($package ? 'for package ' . $package->{id} : 'no package') . ')';
    is($res->code, 201, "create " . $label);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch " . $label);
    my $voucher = JSON::from_json($res->decoded_content);
    $voucher_map->{$voucher->{id}} = $voucher;
    _record_request("create $amount € voucher (code $code)",$request,$req_data,$voucher);
    return $voucher;

}

sub _create_subscriber {
    my ($customer,$record_label) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    {
        lock %subscriber_map;
        my $req_data = {
            domain_id => $domain->{id},
            username => 'cust_subscriber_' . (scalar keys %subscriber_map) . '_'.$t,
            password => 'cust_subscriber_password',
            customer_id => $customer->{id},
            #status => "active",
        };
        $req->content(JSON::to_json($req_data));
        $res = $ua->request($req);
        is($res->code, 201, "POST test subscriber");
        my $request = $req;
        $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
        $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
        $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
        $res = $ua->request($req);
        is($res->code, 200, "fetch POSTed test subscriber");
        my $subscriber = JSON::from_json($res->decoded_content);
        $subscriber->{_label} = 'subscriber' . ($record_label ? ' ' . $record_label : '');
        $subscriber_map{$subscriber->{id}} = threads::shared::shared_clone($subscriber);
        _record_request("create " . $subscriber->{_label},$request,$req_data,$subscriber);
        return $subscriber;
    }
}

sub _perform_topup_voucher {

    my ($subscriber,$voucher) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/topupvouchers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    my $req_data = {
        code => $voucher->{code},
        subscriber_id => $subscriber->{id},
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 204, "perform topup with voucher " . $voucher->{code});
    _record_request("topup by " . $subscriber_map{$subscriber->{id}}->{_label} . " using " . $voucher->{amount} / 100.0 . " € voucher (code $voucher->{code})",$req,$req_data,undef);

}

sub _perform_topup_cash {

    my ($subscriber,$amount,$package) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/topupcash/');
    $req->header('Content-Type' => 'application/json');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    my $req_data = {
        amount => $amount * 100.0,
        package_id => ($package ? $package->{id} : undef),
        subscriber_id => $subscriber->{id},
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 204, "perform topup with amount " . $amount * 100.0 . " cents, " . ($package ? 'package id ' . $package->{id} : 'no package'));
    _record_request("topup by " . $subscriber_map{$subscriber->{id}}->{_label} . " with " . $amount / 100.0 . " €, " . ($package ? 'package id ' . $package->{id} : 'no package'),$req,$req_data,undef);

}

sub _create_billing_profile {
    my ($name,@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    my $req_data = {
        name => $name." $t",
        handle  => $name."_$t",
        reseller_id => $default_reseller_id,
        @further_opts,
    };
    $req->content(JSON::to_json($req_data));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billing profile " . $name);
    my $request = $req;
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billing profile " . $name);
    my $billingprofile = JSON::from_json($res->decoded_content);
    $profile_map->{$billingprofile->{id}} = $billingprofile;
    _record_request("create billing profile '$name'",$request,$req_data,$billingprofile);
    return $billingprofile;
}

sub _get_subscriber_lock_level {
    my ($subscriber) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/subscriberpreferences/'.$subscriber->{id});
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $res = $ua->request($req);
    is($res->code, 200, "fetch subscriber id " . $subscriber->{id} . " preferences");
    my $preferences = JSON::from_json($res->decoded_content);
    return $preferences->{lock};
}

sub _get_actual_billing_profile_id {
    my ($customer) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/customers/'.$customer->{id});
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $res = $ua->request($req);
    is($res->code, 200, "fetch customer id " . $customer->{id});
    my $contract = JSON::from_json($res->decoded_content);
    return $contract->{billing_profile_id};
}

sub _fetch_preferences_worker {
    my ($delay,$sort_column,$dir,$custcontact) = @_;
    diag("starting thread " . threads->tid() . " ...");
    $req = HTTP::Request->new('GET', $uri.'/api/subscriberpreferences/?order_by='.$sort_column.'&order_by_direction='.$dir.'&contact_id='.$custcontact->{id}.'&rows='.(scalar keys %subscriber_map));
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $req->header('X-Delay-Commit' => $delay);
    $res = $ua->request($req);
    is($res->code, 200, "thread " . threads->tid() . ": concurrent fetch subscriber preferences of contracts of contact id ".$custcontact->{id} . " in " . $dir . " order");
    my $result = JSON::from_json($res->decoded_content);
    #is($result->{total_count},(scalar keys %subscriber_map),"check total count");
    diag("finishing thread " . threads->tid() . " ...");
    return $result;
}

sub _fetch_subscribers_worker {
    my ($delay,$sort_column,$dir,$custcontact) = @_;
    diag("starting thread " . threads->tid() . " ...");
    $req = HTTP::Request->new('GET', $uri.'/api/subscribers/?order_by='.$sort_column.'&order_by_direction='.$dir.'&contact_id='.$custcontact->{id}.'&rows='.(scalar keys %subscriber_map));
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;
    $req->header('X-Delay-Commit' => $delay);
    $res = $ua->request($req);
    is($res->code, 200, "thread " . threads->tid() . ": concurrent fetch subscribers of contracts of contact id ".$custcontact->{id} . " in " . $dir . " order");
    my $result = JSON::from_json($res->decoded_content);
    #is($result->{total_count},(scalar keys %subscriber_map),"check total count");
    diag("finishing thread " . threads->tid() . " ...");
    return $result;
}

sub _record_request {
    my ($label,$request,$req_data,$res_data) = @_;
    if ($tb) {
        my $dtf = DateTime::Format::Strptime->new(
            pattern => '%F %T',
        );
        $tb->add(wrap('',"\t",$tb_cnt . ".\t" . $label . ":"),'');
        my $http_cmd = $request->method . " " . $request->uri;
        $http_cmd =~ s/\?/?\n/;
        $tb->add($http_cmd,' ... at ' . $dtf->format_datetime(NGCP::Panel::Utils::DateTime::current_local));
        $tb->add("Request","Response");
        if ($res_data) {
            $res_data = Storable::dclone($res_data);
            delete $res_data->{"_links"};
            $tb->add($req_data ? to_pretty_json($req_data) : '', to_pretty_json($res_data));
        } else {
            $tb->add($req_data ? to_pretty_json($req_data) : '', '');
        }
        $tb_cnt++;
    };
}

sub _set_cash_balance {

    my ($customer,$new_cash_balance) = @_;
    $req = HTTP::Request->new('PATCH', $uri.'/api/customerbalances/' . $customer->{id});
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('X-Fake-Clienttime' => _get_fake_clienttime_now());
    $req->header('X-Request-Identifier' => $req_identifier) if $req_identifier;

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/cash_balance', value => $new_cash_balance } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "setting customer id " . $customer->{id} . " cash_balance to " . $new_cash_balance * 100.0 . ' cents');

}

sub _start_recording {
    $tb = Text::Table->new("request", "response");
    $tb_cnt = 1;
}

sub _stop_recording {
    my $output = '';
    if ($tb) {
        $output = $tb->stringify;
    }
    undef $tb;
    undef $tb_cnt;
    return $output;
}

sub to_pretty_json {
    return JSON::to_json(shift, {pretty => 1}); # =~ s/(^\s*{\s*)|(\s*}\s*$)//rg =~ s/\n   /\n/rg;
}

sub _req_to_debug {
    my $request = shift;
    return { request => $request->method . " " . $request->uri,
            headers => $request->headers };
}

sub _get_allow_delay_commit {
    my $allow_delay_commit = 0;
    my $cfg = $config{api_debug_opts};
    $allow_delay_commit = ((defined $cfg->{allow_delay_commit}) && $cfg->{allow_delay_commit} ? 1 : 0) if defined $cfg;
    return $allow_delay_commit;
}

sub _get_allow_fake_client_time {
    my $allow_fake_client_time = 0;
    my $cfg = $config{api_debug_opts};
    $allow_fake_client_time = ((defined $cfg->{allow_fake_client_time}) && $cfg->{allow_fake_client_time} ? 1 : 0) if defined $cfg;
    return $allow_fake_client_time;
}

#sub _create_gantt_old {
#    my ($customer,$expected_interval_history) = @_;
#
#    if (defined $gantt_events && (scalar @$gantt_events > 0)) {
#
#        use Project::Gantt;
#        use Project::Gantt::Skin;
#
#        my $skin= new Project::Gantt::Skin(
#            doTitle         =>      0);
#
#        my $filename = $req_identifier;
#        $filename =~ s/[^a-z0-9_\-]/_/i;
#        $filename = '/home/rkrenn/test/gantt/' . $filename . '.png';
#        my $gantt = new Project::Gantt(
#            file            =>      $filename,
#            skin            =>      $skin,
#            mode            =>      'months',
#            description     =>      $req_identifier);
#
#        my $dtf = DateTime::Format::Strptime->new(
#            pattern => '%F %T',
#        );
#        foreach my $balance_interval (@$expected_interval_history) {
#            my $start = $balance_interval->{start};
#            $start =~ s/~//;
#            my $end = $balance_interval->{stop};
#            if ('9999-12-31 23:59:59' eq $end) {
#                $end = $dtf->format_datetime(NGCP::Panel::Utils::DateTime::from_string($start)->add(years => 1));
#            } else {
#                $end =~ s/~//;
#            }
#            my @packages = ();
#            if ('ARRAY' eq ref $balance_interval->{package_id}) {
#                foreach my $package_id (@{$balance_interval->{package_id}}) {
#                    if (defined $package_id) {
#                        push(@packages,$package_map->{$package_id}->{description});
#                    } else {
#                        push(@packages,"no package");
#                    }
#                }
#            } else {
#                if (defined $balance_interval->{package_id}) {
#                    push(@packages,$package_map->{$balance_interval->{package_id}}->{description});
#                } else {
#                    push(@packages,"no package");
#                }
#            }
#            my $resource = $gantt->addResource(name => $packages[$#packages]);
#            $gantt->addTask(
#            #description     =>      $package->{name},
#            description     => join(', ',@packages),
#            resource        =>      $resource,
#            start           =>      $start,
#            end             =>      $end);
#        }
#        my $event_count = 1;
#        foreach my $event (@$gantt_events) {
#            my $resource = $gantt->addResource(name => 'event ' . $event_count);
#            $gantt->addTask(
#            #description     =>      $package->{name},
#            description     => $event->{name},
#            resource        =>      $resource,
#            start           =>      $event->{t},
#            end             =>      $dtf->format_datetime(NGCP::Panel::Utils::DateTime::from_string($event->{t})->add(seconds => 1)),
#            );
#            $event_count++;
#        }
#        $gantt->display();
#        return 1;
#    }
#    return 0;
#
#}

sub _create_gantt {

    my ($customer,$expected_interval_history) = @_;

    #uncomment and adjust this, if you want to create gantt charts of
    #contract_balances resulting from a test case. this is a only a
    #proof-of-concept and requires to have ChartDirector library installed.

    #use lib "/opt/ChartDirector/lib/";
    #use perlchartdir;
    #
    #if (defined $gantt_events && (scalar @$gantt_events > 0)) {
    #
    #    my $filename = $req_identifier;
    #    $filename =~ s/[^a-z0-9_\-]/_/i;
    #    $filename = '/home/rkrenn/test/gantt/' . $filename . '.png';
    #
    #    my @startDate = ();
    #    my @endDate = ();
    #    my @labels = ();
    #    my @colors = ();
    #    my @taskNo = ();
    #
    #    my $firstDate = undef;
    #    my $lastDate = undef;
    #
    #    my $dtf = DateTime::Format::Strptime->new(
    #        pattern => '%F %T',
    #    );
    #
    #    my $inf_end = 0;
    #    foreach my $balance_interval (@$expected_interval_history) {
    #        my $start = $balance_interval->{start};
    #        $start =~ s/~//;
    #        my $end = $balance_interval->{stop};
    #        if ('9999-12-31 23:59:59' eq $end) {
    #            $end = $dtf->format_datetime(NGCP::Panel::Utils::DateTime::from_string($start)->add(months => 1));
    #            $inf_end = 1;
    #        } else {
    #            $end =~ s/~//;
    #        }
    #        my @packages = ();
    #        if ('ARRAY' eq ref $balance_interval->{package_id}) {
    #            foreach my $package_id (@{$balance_interval->{package_id}}) {
    #                if (defined $package_id) {
    #                    push(@packages,$package_map->{$package_id}->{description});
    #                } else {
    #                    push(@packages,"no package");
    #                }
    #            }
    #        } else {
    #            if (defined $balance_interval->{package_id}) {
    #                push(@packages,$package_map->{$balance_interval->{package_id}}->{description});
    #            } else {
    #                push(@packages,"no package");
    #            }
    #        }
    #        push(@startDate,perlchartdir::chartTime(split(/[^0-9]+/, $start)));
    #        $firstDate = $start unless $firstDate;
    #        push(@endDate,perlchartdir::chartTime(split(/[^0-9]+/, $end)));
    #        $lastDate = $end;
    #        push(@labels,join(', ',@packages));
    #        push(@colors,0xa0a0a0);
    #        push(@taskNo,scalar @taskNo);
    #    }
    #
    #    $firstDate = perlchartdir::chartTime(split(/[^0-9]+/,$dtf->format_datetime(NGCP::Panel::Utils::DateTime::from_string($firstDate)->subtract(days => 3)->truncate(to => 'day'))));
    #    $lastDate = perlchartdir::chartTime(split(/[^0-9]+/,($inf_end ? $lastDate : $dtf->format_datetime(NGCP::Panel::Utils::DateTime::from_string($lastDate)->add(days => 4)->truncate(to => 'day')))));
    #
    #    # Create a XYChart object of size 620 x 280 pixels. Set background color to light blue (ccccff),
    #    # with 1 pixel 3D border effect.
    #    #my $c = new XYChart(700, 365, 0xccccff, 0x000000, 1);
    #    my $c = new XYChart(1300, 700, 0xccccff, 0x000000, 1);
    #
    #    # Set the plotarea at (140, 55) and of size 460 x 200 pixels. Use alternative white/grey background.
    #    # Enable both horizontal and vertical grids by setting their colors to grey (c0c0c0). Set vertical
    #    # major grid (represents month boundaries) 2 pixels in width
    #    #$c->setPlotArea(180, 55, 500, 200, 0xffffff, 0xeeeeee, $perlchartdir::LineColor, 0xc0c0c0, 0xc0c0c0
    #    $c->setPlotArea(180, 55, 1000, 400, 0xffffff, 0xeeeeee, $perlchartdir::LineColor, 0xc0c0c0, 0xc0c0c0
    #        )->setGridWidth(2, 1, 1, 1);
    #
    #    # swap the x and y axes to create a horziontal box-whisker chart
    #    $c->swapXY();
    #
    #    # Set the y-axis scale to be date scale from Aug 16, 2004 to Nov 22, 2004, with ticks every 7 days
    #    # (1 week)
    #    $c->yAxis()->setDateScale($firstDate, $lastDate, 86400 * 7, 86400 * 1);
    #
    #    # Set multi-style axis label formatting. Month labels are in Arial Bold font in "mmm d" format.
    #    # Weekly labels just show the day of month and use minor tick (by using '-' as first character of
    #    # format string).
    #    $c->yAxis()->setMultiFormat(perlchartdir::StartOfMonthFilter(), "<*font=arialbd.ttf*>{value|mmm d}",
    #        perlchartdir::StartOfDayFilter(), "-{value|d}");
    #
    #    # Set the y-axis to shown on the top (right + swapXY = top)
    #    $c->setYAxisOnRight();
    #
    #    # Set the labels on the x axis
    #    $c->xAxis()->setLabels(\@labels);
    #
    #    # Reverse the x-axis scale so that it points downwards.
    #    $c->xAxis()->setReverse();
    #
    #    # Set the horizontal ticks and grid lines to be between the bars
    #    $c->xAxis()->setTickOffset(0.5);
    #
    #    # Add some symbols to the chart to represent milestones. The symbols are added using scatter layers.
    #    # We need to specify the task index, date, name, symbol shape, size and color.
    #    #$c->addScatterLayer([1], [perlchartdir::chartTime(2004, 9, 13)], "Milestone 1",
    #    #    perlchartdir::Cross2Shape(), 13, 0xffff00);
    #    #$c->addScatterLayer([3], [perlchartdir::chartTime(2004, 10, 4)], "Milestone 2",
    #    #    perlchartdir::StarShape(5), 15, 0xff00ff);
    #    #$c->addScatterLayer([5], [perlchartdir::chartTime(2004, 11, 8)], "Milestone 3",
    #    #    $perlchartdir::TriangleSymbol, 13, 0xff9933);
    #    my $event_count = 0;
    #    my $title = '';
    #    foreach my $event (@$gantt_events) {
    #        $title = $event->{name};
    #        $title =~ s/customer \d+/customer/i;
    #        $c->addScatterLayer([$#taskNo], [perlchartdir::chartTime(split(/[^0-9]+/, $event->{t}))], $title,
    #            perlchartdir::Cross2Shape(), 13, 0xffff00) if $event_count % 3 == 0;
    #        $c->addScatterLayer([$#taskNo], [perlchartdir::chartTime(split(/[^0-9]+/, $event->{t}))], $title,
    #            perlchartdir::StarShape(5), 15, 0xff00ff) if $event_count % 3 == 1;
    #        $c->addScatterLayer([$#taskNo], [perlchartdir::chartTime(split(/[^0-9]+/, $event->{t}))], $title,
    #            $perlchartdir::TriangleSymbol, 13, 0xff9933) if $event_count % 3 == 2;
    #        $event_count++;
    #    }
    #
    #    # Add a title to the chart using 15 points Times Bold Itatic font, with white (ffffff) text on a
    #    # deep blue (000080) background
    #    $c->addTitle($title, "timesbi.ttf", 15, 0xffffff)->setBackground(0x000080);
    #
    #    # Add a multi-color box-whisker layer to represent the gantt bars
    #    my $layer = $c->addBoxWhiskerLayer2(\@startDate, \@endDate, undef, undef, undef, \@colors);
    #    $layer->setXData(\@taskNo);
    #    $layer->setBorderColor($perlchartdir::SameAsMainColor);
    #
    #    # Divide the plot area height ( = 200 in this chart) by the number of tasks to get the height of
    #    # each slot. Use 80% of that as the bar height.
    #    #$layer->setDataWidth(int(200 * 4 / 5 / scalar(@labels)));
    #    $layer->setDataWidth(int(400 * 4 / 5 / scalar(@labels)));
    #
    #    # Add a legend box at (140, 265) - bottom of the plot area. Use 8pt Arial Bold as the font with
    #    # auto-grid layout. Set the width to the same width as the plot area. Set the backgorund to grey
    #    # (dddddd).
    #    #my $legendBox = $c->addLegend2(180, 265, $perlchartdir::AutoGrid, "arialbd.ttf", 8);
    #    #my $legendBox = $c->addLegend2(180, 265, $perlchartdir::AutoGrid, "arialbd.ttf", 8);
    #    my $legendBox = $c->addLegend2(180, 465, $perlchartdir::AutoGrid, "arialbd.ttf", 8);
    #    $legendBox->setWidth(1001);
    #    $legendBox->setBackground(0xdddddd);
    #
    #    # The keys for the scatter layers (milestone symbols) will automatically be added to the legend box.
    #    # We just need to add keys to show the meanings of the bar colors.
    #    $legendBox->addKey("Balance Intervals", 0xa0a0a0);
    #    #$legendBox->addKey("Planning Team", 0x0000cc);
    #    #$legendBox->addKey("Development Team", 0xcc0000);
    #
    #    # Output the chart
    #    $c->makeChart($filename);
    #    return 1;
    #}
    return 0;

}
