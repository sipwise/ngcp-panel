package NGCP::Panel::Utils::Prosody;

use Sipwise::Base;
use Net::Telnet;

sub activate_domain {
    my ($c, $domain) = @_;

    my $t = Net::Telnet->new(Timeout => 1);
    my $hosts = _load_servers($c);
    my $ok = 1;
    foreach my $host(@{ $hosts }) {
        $t->open(Host => $host->{ip}, Port => $host->{port});
        $t->waitfor('/http:\/\/prosody.im\/doc\/console/');
        $t->print("host:activate('$domain')");
        my ($res, $amatch)  = $t->waitfor('/(Result: \w+)|(Message: .+)/');
        if($amatch =~ /Result:\s*true/) {
            # fine
        } else {
            $ok = 0;
        }
        $t->print("host:activate('search.$domain', { component_module = 'sipwise_vjud' })");
        ($res, $amatch)  = $t->waitfor('/(Result: \w+)|(Message: .+)/');
        if($amatch =~ /Result:\s*true/) {
            # fine
        } else {
            $ok = 0;
        }
    }

    return $ok if($ok);
    return;
}

sub deactivate_domain {
    my ($c, $domain) = @_;

    my $t = Net::Telnet->new(Timeout => 1);
    my $hosts = _load_servers($c);
    my $ok = 1;
    foreach my $host(@{ $hosts }) {
        $t->open(Host => $host->{ip}, Port => $host->{port});
        $t->waitfor('/http:\/\/prosody.im\/doc\/console/');
        $t->print("host:deactivate('$domain')");
        my ($res, $amatch)  = $t->waitfor('/(Result: \w+)|(Message: .+)/');
        if($amatch =~ /Result:\s*true/) {
            # fine
        } else {
            $ok = 0;
        }
        $t->print("host:deactivate('search.$domain')");
        ($res, $amatch)  = $t->waitfor('/(Result: \w+)|(Message: .+)/');
        if($amatch =~ /Result:\s*true/) {
            # fine
        } else {
            $ok = 0;
        }
    }

    return $ok if($ok);
    return;
}

sub _load_servers {
    my ($c) = @_;

	my $host_rs = $c->model('DB')->resultset('xmlgroups')
	    ->search_rs({name => 'xmpp'})
	    ->search_related('xmlhostgroups')->search_related('host');
    return [map +{ip => $_->ip, port => $_->port, path => $_->path,
        id => $_->id}, $host_rs->all];
}

1;

# vim: set tabstop=4 expandtab:
