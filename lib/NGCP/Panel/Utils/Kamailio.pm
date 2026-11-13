package NGCP::Panel::Utils::Kamailio;

use Sipwise::Base;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::DateTime;
use Data::Dumper;

sub delete_location_contact {
    my ($c, $aor, $contact) = @_;

    my $ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.rm_contact</methodName>
<params>
<param><value><string>location</string></value></param>
<param><value><string>$aor</string></value></param>
<param><value><string>$contact</string></value></param>
</params>
</methodCall>
EOF

}

sub delete_location {
    my ($c, $aor) = @_;

    my $ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.rm</methodName>
<params>
<param><value><string>location</string></value></param>
<param><value><string>$aor</string></value></param>
</params>
</methodCall>
EOF

}

sub delete_location_by_aor {
    my ($c, $aors) = @_;

    foreach my $aor (@$aors) {
        my $ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.rm</methodName>
<params>
<param><value><string>location</string></value></param>
<param><value><string>$aor</string></value></param>
</params>
</methodCall>
EOF
    }
}

sub create_location {
    my ($c, $prov_subscriber, $params) = @_;
    my($contact, $q, $expires, $flags, $cflags) = @$params{qw/contact q expires flags cflags/};
    my $aor = get_aor($c, $prov_subscriber);
    my $path = _compose_location_path($c, $prov_subscriber, $params);#compose path from path or socket from params
    my $socket = $params->{socket} // 0;

    if ($expires) {
        $expires = NGCP::Panel::Utils::DateTime::from_string($expires)->epoch;
        $expires //= 0;
        $expires -= time();
        # "expires" is required to be an integer but it is not a timestamp
        # <=0:  1970-01-01 00:00:00
        # 1: now
        # >=1: now + seconds to the future
    } else {
        $expires = 4294967295;
    }
    $expires = 0 if $expires < 0;
    $flags //= 0;
    $cflags //= 0;
    my $ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.add</methodName>
<params>
<param><value><string>location</string></value></param>
<param><value><string>$aor</string></value></param>
<param><value><string>$contact</string></value></param>
<param><value><int>$expires</int></value></param>
<param><value><double>$q</double></value></param>
<param><value><string><![CDATA[$path]]></string></value></param>
<param><value><int>$flags</int></value></param>
<param><value><int>$cflags</int></value></param>
<param><value><int>0</int></value></param>
<param><value><int>0</int></value></param>
<param><value><int>$socket</int></value></param>
</params>
</methodCall>
EOF
}

sub flush {
    my ($c) = @_;

    my $ret = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>ul.flush</methodName>
</methodCall>
EOF
}

# returns: () or (ID, STATUS, [XML])
sub trusted_reload {
    my ($c) = @_;

    my ($ret) = NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>permissions.trustedReload</methodName>
</methodCall>
EOF
    return ref $ret ? @{ $ret } : ();
}

sub get_aor{
    my ($c, $prov_subscriber) = @_;
    return $prov_subscriber->username . '@' . $prov_subscriber->domain->domain;
}

sub _compose_location_path {
    my ($c, $prov_subscriber, $params) = @_;
#path: <sip:lb@127.0.0.1;lr;socket=sip:10.15.17.198:5060>
#The "path" uri points to the sip_int on the LB node to which this subscriber belongs.
#The "socket" points to the LB interface from which the incoming calls to this registration should be sent out.
#See detailed description of the implemented logic in the workfron tasks 37459, 14589
#In multi-site setups the LB is taken from the site the socket belongs to
    my $socket = $params->{socket};
    my $path_default = $c->config->{sip}->{path} || '<sip:127.0.0.1:5060;lr>';
    if (!$socket) {
        #user selected default outbound option
        $c->log->debug('_compose_location_path: socket is empty, return default path:'.$path_default);
        return $path_default;
    }
    my $subscriber_lb_ptr_preference_rs = NGCP::Panel::Utils::Preferences::get_chained_preference_rs(
        $c,
        'lbrtp_set',
        $prov_subscriber,
        {
            type => 'usr',
            'order' => [qw/usr prof dom/]
        },
    );
    my ($subscriber_lb_ptr,$subscriber_lb);
    if ($subscriber_lb_ptr_preference_rs && $subscriber_lb_ptr_preference_rs->first) {
        $subscriber_lb_ptr = $subscriber_lb_ptr_preference_rs->first->value;
        $c->log->debug('_compose_location_path: lbrtp_set:'.($subscriber_lb_ptr // 'undef'));
    }

    my ($site_id, $site) = get_socket_site($c, $socket);
    if ($site) {
        $subscriber_lb = select_lb_uri($site->{cluster_sets}, $subscriber_lb_ptr, $site->{lb_uri});
        if ($subscriber_lb) {
            $c->log->debug("_compose_location_path: using LB of site $site_id for socket $socket");
        } else {
            $c->log->warn("_compose_location_path: no LB configured for site $site_id of socket $socket, using local LB");
        }
    }
    #TODO: is it ok to use default 'sip:lb@127.0.0.1:5060;lr' here?
    $subscriber_lb //= select_lb_uri($c->config->{cluster_sets}, $subscriber_lb_ptr, 'sip:lb@127.0.0.1:5060;lr');
    my $path = '<'.$subscriber_lb.';socket='.$socket.'>';
    $c->log->debug('_compose_location_path: path:'.$path);
    return $path;
}

sub select_lb_uri {
    my ($cluster_sets, $lb_ptr, $fallback) = @_;
    $cluster_sets = {} unless ref $cluster_sets eq 'HASH';
    $lb_ptr //= $cluster_sets->{default};
    my $lb_uri = defined $lb_ptr ? $cluster_sets->{$lb_ptr} : undef;
    return $lb_uri // $fallback;
}

sub get_socket_site {
    my ($c, $socket) = @_;

    my $multisite = $c->config->{multisite} // {};
    my $sites = $multisite->{sites};
    return unless $multisite->{site_id} && ref $sites eq 'HASH' && $socket;

    # the web form shows udp sockets as sip:
    my @values = ($socket);
    push @values, "udp:$1" if $socket =~ /^sip:(.+)$/;
    push @values, "sip:$1" if $socket =~ /^udp:(.+)$/;

    my @labels = map { $_->label } $c->model('DB')->resultset('voip_preferences_enum')->search_rs({
        'preference.attribute' => 'outbound_socket',
        'me.value' => { -in => \@values },
    },{
        join => 'preference',
        columns => [qw/me.label/],
    })->all;

    my ($site_id, $error) = site_from_socket_labels($sites, $multisite->{site_id}, \@labels);
    unless (defined $site_id) {
        $c->log->warn("get_socket_site: cannot resolve site of socket $socket ($error), using local LB");
        return;
    }
    return ($site_id, $sites->{$site_id});
}

sub site_from_socket_labels {
    my ($sites, $local_site_id, $labels) = @_;

    return (undef, 'no sites configured') unless ref $sites eq 'HASH';
    return (undef, 'socket not found in outbound_socket list') unless $labels && @$labels;

    my %site_id_by_key = map {
        my $key = ref $sites->{$_} eq 'HASH' ? $sites->{$_}{key} : undef;
        defined $key && length $key ? ($key => $_) : ();
    } keys %{$sites};

    my %matched;
    foreach my $label (@{$labels}) {
        next unless defined $label && $label =~ /^([^:]+):/;
        my $id = $site_id_by_key{$1} // next;
        $matched{$id} = 1;
    }

    my @ids = sort keys %matched;
    return (undef, 'no site matches the socket labels') unless @ids;
    return ($ids[0]) if @ids == 1;
    return ($local_site_id) if defined $local_site_id && $matched{$local_site_id};
    return (undef, 'socket matches multiple sites: '.join(',', @ids));
}

1;

# vim: set tabstop=4 expandtab:
