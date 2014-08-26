package NGCP::Panel::Utils::Message;

use Catalyst;
use Sipwise::Base;
use Data::Dumper;
use DateTime qw();
use DateTime::Format::RFC3339 qw();
use Time::HiRes qw();

method get_log_params ($self: Catalyst :$c, :$data?) {
    # get log_tx_id, caller method, remote user, formatted passed parameters

    # tx_id
    my $log_tx = DateTime->from_epoch(epoch => Time::HiRes::time);
    my $log_tx_id = sprintf '%X', $log_tx->strftime('%s%N');

    # package and method
    my $caller = (caller 2)[3];
    $caller !~ /::/ and $caller = (caller 3)[3];
    my $called = '';
    if ($caller) {
        my @caller = split('::', $caller);
        $#caller >= 3 and $called = join('::', @caller[-3...-1]);
    }

    # remote user
    my $r_user = '';
    if ($c->user->roles eq 'admin' || $c->user->roles eq 'reseller') {
        $r_user = $c->user->login;
    } else {
        $r_user = $c->user->webusername . '@' . $c->user->domain->domain;
    }

    # remote ip
    my $r_ip = $c->request->address;
    $r_ip =~ s/^::ffff://; # ipv4 in ipv6 form -> ipv4

    # parameters
    my $data_str = Data::Dumper->new([ $data ? $data : $c->request->parameters ])
                               ->Terse(1)
                               ->Dump;
    $data_str =~ s/\n//g;
    $data_str =~ s/\s+/ /g;

    unless ($c->config->{logging}->{clear_passwords}) {
    }

    return {
                tx_id  => $log_tx_id,
                called => $called,
                r_user => $r_user,
                r_ip   => $r_ip,
                data   => $data_str,
           };
}

method error ($self: Catalyst :$c, Str :$desc, Str :$log?, :$error?, :$data?) {
# we explicitly declare the invocant to skip the validation for Object
# because we want a class method instead of an object method

    my $log_params = $self->get_log_params(c => $c, data => $data);

    my $log_msg = '';
    my $usr_type = 'error';
    my $usr_text = $desc;

    given (1) {
        when (defined $log)
        {
            $log_msg = $log
        }
        when (not defined $error)
        {
            $log_msg = $desc;
        }
        when (my ($host) = $error =~ /problem connecting to (\S+, port [0-9]+)/ )
        {
            $log_msg  = "$desc ($error)";
            $usr_text = "$desc (A service could not be reached, $host)";
        }
        when (ref($error) eq "ARRAY" && @$error >= 2 && $error->[1] eq "showdetails" )
        {
            $log_msg  = "$desc (@$error[0])";
            $usr_text = "$desc (@$error[0])";
        }
        when (not $error->isa('DBIx::Class::Exception') )
        {
            $log_msg  = "$desc ($error)";
            $usr_text = $desc;
        }
        when (my ($dup) = $error =~ /(Duplicate entry \S*)/ )
        {
            $log_msg  = "$desc ($error)";
            $usr_text = "$desc ($dup)";
        }
        when (my ($excerpt) = $error =~ /(Column \S+ cannot be null)/ ) {
            $log_msg  = "$desc ($error)";
            $usr_text = "$desc ($excerpt)";
        }
        default {
            $log_msg = "$desc ($error)";
        }
    }

    $c->log->error(
        sprintf <<EOF, @{$log_params}{qw(r_ip called tx_id r_user data)});
IP=%s CALLED=%s TX=%s USER=%s DATA=%s MSG=$log_msg
EOF
    $c->flash(messages => [{ type => $usr_type,
                             text => sprintf '%s [%s]',
                                        $usr_text,
                                        $log_params->{tx_id},
                            }]);
    return;
}

method info ($self: Catalyst :$c, Str :$desc, Str :$log?, :$data?) {
# we explicitly declare the invocant to skip the validation for Object
# because we want a class method instead of an object method

    my $log_params = $self->get_log_params(c => $c, data => $data);

    my $log_msg = '';
    my $usr_type = 'info';
    my $usr_text = $desc;

    given (1) {
        when (defined $log)
        {
            $log_msg = $log
        }
        default
        {
            $log_msg = $desc;
        }
    }

    $c->log->info(
        sprintf <<EOF, @{$log_params}{qw(r_ip called tx_id r_user data)});
IP=%s CALLED=%s TX=%s USER=%s DATA=%s MSG=$log_msg
EOF
    $c->flash(messages => [{ type => $usr_type, text => $usr_text }]);
    return;
}

__END__

=encoding UTF-8

=head1 NAME

NGCP::Panel::Utils::Message

=head1 DESCRIPTION

Parse messages for log and Web display.

=head1 INTERFACE

=head2 Functions

=head3 C<get_log_params>

Params: c (required)

Returns a hash ref with basic logging parameters that are used in "error", "info".

=head3 C<error>

Params: c (required), desc (required), error, log

Parse Exceptions (mainly DBIx::Class::Exceptions) and show the relevant
bits on the panel. Also log everything to the logger.

=head3 C<info>

Params: c (required), desc (required), log

Shows the info message on the panel. Also logs everything to the logger.

=head1 AUTHOR

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.
