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
    my ($c, $prov_subscriber, $contact, $q, $expires, $flags, $cflags) = @_;

    my $aor = get_aor($c, $prov_subscriber);
    my $path = $c->config->{sip}->{path} || '<sip:127.0.0.1:5060;lr>';
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
1;

# vim: set tabstop=4 expandtab:
