package NGCP::Panel::Utils::Rewrite;

use strict;
use warnings;

use NGCP::Panel::Utils::XMLDispatcher;

sub sip_dialplan_reload {
    my ($c) = @_;
    NGCP::Panel::Utils::XMLDispatcher::dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>dialplan.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

1;

# vim: set tabstop=4 expandtab:
