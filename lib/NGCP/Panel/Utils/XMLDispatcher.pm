package NGCP::Panel::Utils::XMLDispatcher;

use Sipwise::Base;
use Net::HTTP;
use Errno;

sub dispatch {
    my ($c, $target, $all, $sync, $body, $schema) = @_;

    $schema //= $c->model('DB');
    $c->log->info("dispatching to target $target, all=$all, sync=$sync");
    $c->log->debug("dispatching body $body");

    my $hosts;
    if ($target =~ /^%TG%/) {
        my @t = split(/::/, $target);
        $hosts = [{ip => $t[2], port => $t[3], path => $t[4], id => $t[5]}];
    }
    else {
        my $host_rs = $schema->resultset('xmlgroups')
            ->search_rs({name => $target})
            ->search_related('xmlhostgroups')->search_related('host', {}, { order_by => 'id' });
        $hosts = [map { +{ip => $_->ip, port => $_->port, path => $_->path,
            id => $_->id} } $host_rs->all];
        use DDP; p $hosts;
    }

    use Data::Dumper;
    $c->log->info("dispatching to hosts: " . Dumper $hosts);
    my @ret;

    for my $host (@$hosts) {
        my ($meth, $ip, $port, $path, $hostid) = ("http", $host->{ip}, $host->{port}, $host->{path}, $host->{id});
        $c->log->info("dispatching xmlrpc $target request to ".$ip.":".$port.$path);

        my $ret = eval {    # catch exceptions
            my $s = Net::HTTP->new(Host => $ip, KeepAlive => 0, PeerPort => $port || 80, Timeout => 5);
            $s or die "could not connect to server";

            my $res = $s->write_request("POST", $path || "/", "User-Agent" => "Sipwise XML Dispatcher", "Content-Type" => "text/xml", $body);
            $res or die "did not get result";

            my ($code, $mess, @headers) = $s->read_response_headers();
            $code == 200 or die "code is $code";

            my $body = "";
            for (;;) {
                my $buf;
                my $n = $s->read_entity_body($buf, 1024);
                if (!defined($n) || $n == -1) {
                    $!{EINTR} || $!{EAGAIN} and next;
                    die;
                }
                $n == 0 and last;

                $body .= $buf;
            }

            # successful request

            return [$hostid, 1, $body]; # return from eval only
        };

        if ($ret) {
            return $ret
                unless $all;
            push(@ret, $ret);
            next;
        }

        # failure
        
        $c->log->info("failure: $@");

        $all or next;

        if ($sync) {
            push(@ret, [$hostid, 0]);
            next;
        }

        _queue(join("::", "%TG%", $meth, $ip, $port, $path, $hostid), $body, $schema);
        push(@ret, [$hostid, -1]);
    }

    if (!$all) {
        # failure on all hosts
        $sync and return;
        _queue($target, $body, $schema);
        return [$target, -1];
    }

    return wantarray ? @ret : \@ret;
}

sub _queue {
    my ($target, $body, $schema) = @_;

    $schema->resultset('xmlqueue')->create({
        target => $target,
        body => $body,
        ctime => \"unix_timestamp()",
        atime => \"unix_timestamp()",
    });
}

sub queuerunner {
    my ($schema) = @_;

    for (;; sleep(1)) {
        my $row = _dequeue($schema);
        $row or next;

        my @ret = dispatch(undef, $row->target, 0, 1, $row->body, $schema);

        @ret and _unqueue($row->id, $schema);
    }
}

sub _dequeue {
    my ($schema) = @_;

    my $row = $schema->resultset('xmlqueue')->search({
            next_try => {'<=' => \'unix_timestamp()'},
        },{
            order_by => 'id'
        })->first;
    $row or return;

    $row->update({
        tries => \'tries+1',
        atime => \'unix_timestamp()',
        next_try => \['unix_timestamp() + ?', [{} => 5 + $row->tries * 30]],
    });

    return $row;
}

sub _unqueue {
    my ($id, $schema) = @_;

    $schema->resultset('xmlqueue')->find($id)->delete;
}

# dies if unsuccessful
sub sip_domain_reload {
    my ($c, $domain_name) = @_;

    my $NUM_TRIES = 3;
    my $SLEEP_BEFORE_RETRY = 1;
    my $res;

    my $reload_command = <<EOF;
<?xml version="1.0" ?>
<methodCall>
<methodName>domain.reload</methodName>
<params/>
</methodCall>
EOF

    my $dump_command = <<EOF;
<?xml version="1.0" ?>
<methodCall>
<methodName>domain.dump</methodName>
<params/>
</methodCall>
EOF

    for (my $i = 0; $i < $NUM_TRIES; $i++) {
        sleep $SLEEP_BEFORE_RETRY if ($i > 0);

        ($res) = dispatch($c, "proxy-ng", 1, 1, $reload_command); # we're only checking first host here
        if ($res->[1] < 1) {
            die "couldn't reload domains";
        }
        return () unless $domain_name;
        my @replies = dispatch($c, "proxy-ng", 1, 1, $dump_command);
        my $all_successful = 1;
        for my $reply (@replies) {
            if ($reply->[1] && $reply->[2] =~ m/$domain_name/) {
                # successful
            } else {
                $c->log->debug("Domain not loaded. Retrying...");
                $all_successful = 0;
            }
        }
        if ($all_successful) {
            $c->log->debug("Domain successfully loaded in all proxies");
            return;
        }
    }

    die "couldn't load domain into all proxies. Tried $NUM_TRIES times.";
}


1;

=head1 NAME

NGCP::Panel::Utils::XMLDispatcher

=head1 DESCRIPTION

Send XMLRPC notification messages to other services.

=head1 METHODS

=head2 dispatch

This is ported from ossbss/lib/Sipwise/Provisioning/XMLDispatcher.pm

  Send one XML request to one host or one group of hosts.
  @RET = $c->dispatch(TARGET, ALL, SYNC, BODY);
  TARGET: the name of a XMLRPC control service role, as stored in the DB.
  example: "proxy"
  ALL: boolean flag. if true, send the request to all hosts in a group,
  otherwise send the request to any one host in the group.
  SYNC: boolean flag. if true, do not queue any requests, but instead
  return failure on failed requests. 
  BODY: the xml body to send.

  Return value @RET is an array with one element per sent or attempted
  request. Each element of the array is an array reference with two
  or three elements, [ ID, STATUS, XML ] with XML being optional.
  ID is the ID of the host from the DB that the request was sent to,
  or attempted to send to. STATUS is 1 if the request was successful,
  0 if it failed and -1 if it failed and was queued. If the status is
  1, the XML element will be present and contain the XML response body.
  An empty array will be returned if ALL==false and SYNC==true and the
  request failed on all hosts.

=head2 _queue

Save a new target to provisioning.xmlqueue.

=head2 queuerunner

Continuously processes provisioning.xmlqueue.

=head2 _dequeue

Update provisioning.xmlqueue and return one of its rows.

=head2 _unqueue

Remove one row from provisioning.xmlqueue determined by id.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
