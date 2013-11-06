use Sipwise::Base;
use Test::More;

BEGIN {
    use_ok ('Catalyst::Test', 'NGCP::Panel');
    use_ok 'NGCP::Panel::Controller::Administrator';
    use_ok 'NGCP::Panel::Controller::Billing';
    use_ok 'NGCP::Panel::Controller::Callflow';
    use_ok 'NGCP::Panel::Controller::Contact';
    use_ok 'NGCP::Panel::Controller::Contract';
    use_ok 'NGCP::Panel::Controller::Customer';
    use_ok 'NGCP::Panel::Controller::Dashboard';
    use_ok 'NGCP::Panel::Controller::Device';
    use_ok 'NGCP::Panel::Controller::Domain';
    use_ok 'NGCP::Panel::Controller::Login';
    use_ok 'NGCP::Panel::Controller::Logout';
    use_ok 'NGCP::Panel::Controller::NCOS';
    use_ok 'NGCP::Panel::Controller::Peering';
    use_ok 'NGCP::Panel::Controller::Product';
    use_ok 'NGCP::Panel::Controller::Reseller';
    use_ok 'NGCP::Panel::Controller::Rewrite';
    use_ok 'NGCP::Panel::Controller::Root';
    use_ok 'NGCP::Panel::Controller::Security';
    use_ok 'NGCP::Panel::Controller::Sound';
    use_ok 'NGCP::Panel::Controller::Statistics';
    use_ok 'NGCP::Panel::Controller::Subscriber';
}

my @controller_paths = ('/administrator','/billing','/callflow','/contact',
    '/contract','/customer','/dashboard','/device','/domain','/logout',
    '/ncos','/peering','/reseller','/rewrite','/security',
    '/sound','/statistics','/subscriber');
for my $path (@controller_paths) {
    ok(request($path)->is_redirect, "$path should redirect" );
}

ok( request('/login')->is_success, '/login should succeed' );

done_testing();

