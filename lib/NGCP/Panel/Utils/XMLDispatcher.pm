package NGCP::Panel::Utils::XMLDispatcher;

use Sipwise::Base;
use NGCP::Panel::Utils::HTTPDispatcher;

sub dispatch {
    my ($c, $target, $all, $sync, $body, $schema) = @_;
    return NGCP::Panel::Utils::HTTPDispatcher::dispatch($c, $target, $all, $sync, "POST", "text/xml", $body, $schema);
}

# dies if unsuccessful
sub sip_domain_reload {
    my ($c, $domain_name) = @_;

    my $reload_command = <<EOF;
<?xml version="1.0" ?>
<methodCall>
<methodName>domain.reload</methodName>
<params/>
</methodCall>
EOF

    sleep(2);
    my @ret = dispatch($c, "proxy-ng", 1, 1, $reload_command); # we're only checking first host here

    if (grep { $_->[1] == 0 } @ret) {
        die "Couldn't reload domain";
    }

    $c->log->debug("Domain successfully loaded in all active proxies");

    return;
}


1;

=head1 NAME

NGCP::Panel::Utils::XMLDispatcher

=head1 DESCRIPTION

Send XML notification messages to other services.

=head1 METHODS

=head2 dispatch

  This is a wrapper around HTTPDispatcher that has XMLRPC-specific values hard
  coded, for backwards compatibility.

=head1 AUTHOR

Richard Fuchs C<< <rfuchs@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
