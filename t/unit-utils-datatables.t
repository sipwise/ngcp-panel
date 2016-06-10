use warnings;
use strict;

use Test::More;
use Test::MockObject;
use NGCP::Panel::Utils::Datatables;

ok(1, "stub");

use DDP;
my ($columns, $request);

$columns = NGCP::Panel::Utils::Datatables::set_columns(undef, [
    { name => "id", search => 0, title => "#" },
    { name => "name", search => 1, title => "Name" },
    { name => "reseller.name", search => 1, title => "Reseller" },
    { name => "timely", search_from_epoch => 1, search_to_epoch => 1, title => "Timely Value"},
]);
$request = {sSearch => 'bar',
    sSearch_0 => '2016-01-01',
    sSearch_1 => '2016-01-31',
    };
_test_datatables_process(columns => $columns, request => $request);

sub _test_datatables_process {
    my %args = @_;
    my $columns = $args{columns};
    my $request_params = $args{request} // {};

    ############# start mock functionality
    my $c = Test::MockObject->new();
    my $resultset = Test::MockObject->new();
    my $request = Test::MockObject->new();
    my $stash = {};

    $request->set_always('params', $request_params);
    $c->set_always('request',$request);
    my $search_mock_sub = sub {
         # DBIx::Class is so TIMTOWTDI, we can't possibly validate correct behaviour at this level
         # one way would be a mock-in-memory db, and checking whether the correct rows are returned
         # but then we shouldn't call this "unit-test" anymore :)
        shift; p @_;
        return $resultset;
        };
    $resultset->mock('search_rs', $search_mock_sub);
    $resultset->mock('search', $search_mock_sub);
    $resultset->set_series('count', 99, 98);
    $c->mock('stash', sub{
        shift; my %stash_args = @_;
        @$stash{keys %stash_args} = values %stash_args;
        });
    ############# end mock functionality

    $request_params->{sEcho} = "9251";

    NGCP::Panel::Utils::Datatables::process($c, $resultset, $columns);

    p $stash;
    ok(1, "_test_datatables_process completed successfully");
    is($stash->{sEcho}, 9251, "sEcho was properly set");
    is($stash->{iTotalRecords}, 99, "totalRecords were retrieved by first call of count()");
        # not a neccessary conditon for correct functionality, but a hint
    return;
}

done_testing;