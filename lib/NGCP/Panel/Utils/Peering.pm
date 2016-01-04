package NGCP::Panel::Utils::Peering;
use NGCP::Panel::Utils::XMLDispatcher;

use strict;
use warnings;

sub _sip_lcr_reload {
    my(%params) = @_;
    my($c) = @params{qw/c/};
    my $dispatcher = NGCP::Panel::Utils::XMLDispatcher->new;
    $dispatcher->dispatch($c, "proxy-ng", 1, 1, <<EOF );
<?xml version="1.0" ?>
<methodCall>
<methodName>lcr.reload</methodName>
<params/>
</methodCall>
EOF

    return 1;
}

1;

=head1 NAME

NGCP::Panel::Utils::Peering

=head1 DESCRIPTION

A temporary helper to manipulate peerings related data

=head1 METHODS

=head2 _sip_lcr_reload

This is ported from ossbss.

Reloads lcr cache of sip proxies.

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
