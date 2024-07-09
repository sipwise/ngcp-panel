package NGCP::Panel::Utils::License;
use strict;
use warnings;

use Sipwise::Base;

sub get_license_status {
    my ($ref) = @_;

    my $fd;
    {
        no autodie qw(open);
        if (!open($fd, '<', '/proc/ngcp/check')) {
            return 'missing';
        }
    }
    my $status = <$fd>;
    close($fd);
    chomp($status);
    if ($status =~ /^ok/) {
        return 'ok';
    }
    if ($status =~ /missing license/) {
        return 'missing';
    }
    if ($status =~ /^(warning|error) \((.*)\)$/) {
        if (ref($ref) eq 'SCALAR') {
            $$ref = $2;
        }
        return $1;
    }

    if (ref($ref) eq 'SCALAR') {
        $$ref = 'internal error';
    }
    return 'error';
}

sub is_license_status {
    my (@allowed) = @_;
    my $status = get_license_status();
    return scalar grep {$_ eq $status} @allowed;
}

sub is_license_error {
    my (@allowed) = @_;
    @allowed or @allowed = ('error');
    my $ext;
    my $status = get_license_status(\$ext);
    if (!grep {$_ eq $status} @allowed) {
        return 0;
    }
    return $ext || $status;
}

sub get_licenses {
    my $c = shift;

    my $proc_dir = '/proc/ngcp/flags';
    unless (-d $proc_dir) {
        $c->log->error("Failed to access $proc_dir");
        return;
    };

    my @lics = ();
    opendir(my $dh, $proc_dir) || do {
        $c->log->error("Failed to open licenses dir $proc_dir: $!");
        return;
    };
    while (readdir($dh)) {
        my $lf = $_;
        next if $lf =~ /^\.+$/;
        open(my $fh, '<', "$proc_dir/$lf") || do {
            $c->log->error("Failed to open license file $lf: $!");
            next;
        };
        my $enabled = <$fh>;
        chomp($enabled) if $enabled;
        push @lics, $lf if $enabled && $enabled == 1;
        close $fh;
    }
    closedir $dh;
    my @sorted_lics = sort @lics;
    return \@sorted_lics;
}

1;

=head1 NAME

NGCP::Panel::Utils::License

=head1 DESCRIPTION

Helper module for license handling

=head1 METHODS

=head2 get_license_status

Performs the actual check of the license status. Returns one of:

'missing': No license data present.
'ok': License present and all limits observed.
'warning': License present but some limits exceeded within the grace thresholds.
'error': License limits exceeded beyond the grace thresholds, or internal error.

A reference to a scalar can be passed as an optional first argument, in which case
a more detailed status description is written into that scalar in the 'warning'
and 'error' cases.

Example:
my $status = get_license_status(\$ext_status);

=head2 is_license_status

Takes a list of strings as argument list. Returns true or false if the license
status is one of the status names given in the argument list.

Example:
if (is_license_status(qw(missing error))) ...

=head2 is_license_error

Similar to is_license_status() but returns the status string instead of true if
the license status is one of the values given. If the argument list is empty, it
defaults to ('error').

Example:
if (my $status = is_license_error()) ...

=head1 AUTHOR

Richard Fuchs

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
