use threads qw();
#use Sipwise::Base;
use Test::More;



BEGIN {
    unshift(@INC,'../../lib');
}
use NGCP::Panel::Utils::DateTime qw();

my $delay = 5;
my $t_a = threads->create(sub {
    diag('thread ' . threads->tid());
    sleep($delay);
});

my $t_b = threads->create(sub {
    diag('thread ' . threads->tid());
    sleep($delay);
});

$t_a->join();
$t_b->join();

ok(1,'threads joined');
#ok($t_a + $t_b == 2,'test threads joined');

done_testing;
