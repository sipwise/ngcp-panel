package NGCP::Panel::Utils::HeaderManipulations;

use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime;

sub update_condition {
    my %params = @_;
    my ($c, $item, $resource) = @params{qw/c item resource/};

    my $schema = $c->model('DB');

    my $values = delete $resource->{values} // [];
    map { $_->{condition_id} = $item->id } @{$values};

    $item->update($resource);
    $item->values->delete;

    $schema->resultset('voip_header_rule_condition_values')
        ->populate($values);

    $resource->{values} = $values;
    $item->discard_changes()
}

sub invalidate_ruleset {
    my %params = @_;
    my ($c, $set_id) = @params{qw/c set_id/};

    my $schema = $c->model('DB');
    my $path   = "/hm_invalidate_ruleset/";
    my $target = "proxy-ng";

    $c->log->info("invalidate ruleset to target=$target path=$path set_id=$set_id");

    my $hosts;
    my $host_rs = $schema->resultset('xmlgroups')
        ->search_rs({name => $target})
        ->search_related('xmlhostgroups')->search_related('host', {}, { order_by => 'id' });
    $hosts = [map { +{ip => $_->ip, port => $_->port,
                      id => $_->id} } $host_rs->all];

    my %headers = (
                    "User-Agent" => "Sipwise HTTP Dispatcher",
                    "Content-Type" => "text/plain",
                    "P-NGCP-HM-Invalidate-Rule-Set" => $set_id,
                  );

    my @err;

    foreach my $host (@$hosts) {
        my ($method, $ip, $port, $id) =
            ("http", $host->{ip}, $host->{port}, $host->{id});
        my $hostid = "id=$id $ip:$port";
        $c->log->info("dispatching http request to ".$hostid.$path);

        eval {
            my $s = Net::HTTP->new(Host => $ip, KeepAlive => 0, PeerPort => $port, Timeout => 5);
            $s or die "could not connect to server $hostid";

            my $res = $s->write_request("POST", $path || "/", %headers, $set_id);
            $res or die "did not get result from $hostid";

            my ($code, $status, @hdrs) = $s->read_response_headers();
            unless ($code == 200) {
                push @err, "$hostid: $code $status";
            }
        };

        if ($@) {
            my $msg = "$hostid: $@";
            push @err, $msg;
            $c->log->info("failure: $msg");
        }
    }

    return \@err;
}

1;
