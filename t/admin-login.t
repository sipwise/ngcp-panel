use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is)];
use Test::WebDriver::Sipwise qw();

my $d = Test::WebDriver::Sipwise->new;
$d->get($ENV{CATALYST_SERVER});

$d->find(link_text => 'Admin')->click;

$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->find(name => 'submit')->click;

is($d->get_text('//title'), 'Dashboard');

done_testing;
