package NGCP::Panel::Utils::Kamailio;

use Sipwise::Base;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::DateTime;
use Data::Dumper;

sub delete_location_contact {
    my ($c, $prov_subscriber, $contact) = @_;

    my $aor = $prov_subscriber->username . '@' . $prov_subscriber->domain->domain;
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
    my ($c, $prov_subscriber) = @_;

    my $aor = $prov_subscriber->username . '@' . $prov_subscriber->domain->domain;
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

sub create_location {
    my ($c, $prov_subscriber, $params) = @_;
    my($contact, $q, $expires, $flags, $cflags) = @$params{qw/contact q expires flags cflags/};
    my $aor = get_aor($c, $prov_subscriber);
    my $path = _compose_location_path($c, $prov_subscriber, $params);#compose path from path or socket from params
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
#path: <sip:lb@127.0.0.1;lr;received=sip:10.15.17.50:32997;socket=sip:10.15.17.198:5060>
#The "path" uri points to the sip_int on the LB node to which this subscriber belongs.
#The "received" parameter uri is equal to the contact provided in the registrations.
#The "socket" points to the LB interface from which the incoming calls to this registration should be sent out.
#See detailed description of the implemented logic in the workfron tasks 37459, 14589 
    my $socket = $params->{socket};
    my $path_default = $c->config->{sip}->{path} || '<sip:127.0.0.1:5060;lr>';
    if (!$socket) {
        #user selected default outbound option
        $c->log->debug('_compose_location_path: socket is empty, return default path:'.$path_default);
        return $path_default;
    }
    my $lb_clusters = $c->config->{cluster_sets};
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
        $c->log->debug('_compose_location_path: lbrtp_set:'.$subscriber_lb_ptr_preference_rs->first->value);
        $subscriber_lb_ptr = $subscriber_lb_ptr_preference_rs->first->value;
    }
    $subscriber_lb_ptr //= $lb_clusters->{default};
    #TODO: is it ok to use default 'sip:lb@127.0.0.1:5060;lr' here?
    $subscriber_lb = $lb_clusters->{$subscriber_lb_ptr} // 'sip:lb@127.0.0.1:5060;lr';
    my $path = '<'.$subscriber_lb.';received='.$params->{contact}.';socket='.$socket.'>';
    $c->log->debug('_compose_location_path: path:'.$path);
    return $path;
}

1;

# vim: set tabstop=4 expandtab:
