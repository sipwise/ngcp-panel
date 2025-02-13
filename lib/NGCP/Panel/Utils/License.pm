package NGCP::Panel::Utils::License;
use strict;
use warnings;

use Sipwise::Base;
use List::Util qw(none);

use Fcntl;
use IO::Select;

sub get_license_status {
    my ($c, $ref) = @_;

    my $fd;
    {
        no autodie qw(sysopen);
        if (!sysopen($fd, '/proc/ngcp/check', O_NONBLOCK|O_RDONLY)) {
            $c->log->error('License status check failed: could not check license')
                unless $c->config->{general}{ngcp_type} eq 'spce';
            return 'missing';
        }
    }
    my $status = '';
    my @h = IO::Select->new($fd)->can_read(1);
    map { $status = <$_> } @h;
    close($fd);
    unless ($status) {
        $c->log->error('License status check failed: missing license');
        return 'missing';
    }
    chomp($status);
    if ($status =~ /^ok/) {
        return 'ok';
    }
    if ($status =~ /missing license/) {
        $c->log->error("License status check failed: $status");
        return 'missing';
    }
    if ($status =~ /^(warning|error) \((.*)\)$/) {
        if (ref($ref) eq 'SCALAR') {
            $$ref = $status;
        }
        if ($status =~ /^warning/) {
            # do not spam logs with warnings as it's related to graceful thresholds
        } else {
            $c->log->error("License status check failed: $status");
        }
        return $status;
    }

    if (ref($ref) eq 'SCALAR') {
        $$ref = 'internal error';
    }
    $c->log->error("License status check failed: internal error");
    return 'error';
}

sub is_license_status {
    my $c = shift;
    my @allowed = @_;
    my $status = get_license_status($c);
    return scalar grep {$_ eq $status} @allowed;
}

sub is_license_error {
    my $c = shift;
    my @allowed = @_;
    @allowed or @allowed = ('error');
    my $ext;
    my $status = get_license_status($c, \$ext);
    if (!grep {$_ eq $status} @allowed) {
        return 0;
    }
    return $ext || $status;
}

sub get_license {
    my ($c, $lic_name) = @_;

    return 1 if $c->config->{general}{ngcp_type} eq 'spce';

    my $proc_dir = '/proc/ngcp/flags';
    unless (-d $proc_dir) {
        $c->log->error("Failed to access $proc_dir")
            unless $c->config->{general}{ngcp_type} eq 'spce';
        return;
    };

    my $lic_file = $proc_dir . '/' . $lic_name;
    return unless (-r $lic_file);

    sysopen(my $fd, "$lic_file", O_NONBLOCK|O_RDONLY) || do {
        $c->log->error("Failed to open license file $lic_name: $!");
        return;
    };
    my $enabled;
    my @h = IO::Select->new($fd)->can_read(1);
    map { $enabled = <$_> } @h;
    close $fd;
    chomp($enabled) if defined $enabled;

    return $enabled;
}

sub get_licenses {
    my $c = shift;

    my $proc_dir = '/proc/ngcp/flags';
    unless (-d $proc_dir) {
        $c->log->error("Failed to access $proc_dir")
            unless $c->config->{general}{ngcp_type} eq 'spce';
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
        sysopen(my $fd, "$proc_dir/$lf", O_NONBLOCK|O_RDONLY) || do {
            $c->log->error("Failed to open license file $lf: $!");
            next;
        };
        my $enabled;
        my @h = IO::Select->new($fd)->can_read(1);
        map { $enabled = <$_> } @h;
        close $fd;
        chomp($enabled) if defined $enabled;
        push @lics, $lf if $enabled && $enabled == 1;
    }
    closedir $dh;
    my @sorted_lics = sort @lics;
    return \@sorted_lics;
}

sub get_license_meta {
    my $c = shift;

    my $proc_dir = '/proc/ngcp';
    unless (-d $proc_dir) {
        $c->log->error("Failed to access $proc_dir")
            unless $c->config->{general}{ngcp_type} eq 'spce';
        return;
    };

    my $meta = {};
    my @collect = qw(
        check
        current_calls
        current_pbx_groups
        current_pbx_subscribers
        current_registered_subscribers
        current_subscribers
        license_valid_until
        max_calls
        max_pbx_groups
        max_pbx_subscribers
        max_registered_subscribers
        max_subscribers
        valid
    );

    opendir(my $dh, $proc_dir) || do {
        $c->log->error("Failed to open ngcp dir $proc_dir: $!");
        return;
    };
    while (readdir($dh)) {
        my $lf = $_;
        next if $lf =~ /^\.+$/;
        next if none { $lf eq $_ } @collect;
        sysopen(my $fd, "$proc_dir/$lf", O_NONBLOCK|O_RDONLY) || do {
            $c->log->error("Failed to open license file $lf: $!");
            next;
        };
        my $value;
        my @h = IO::Select->new($fd)->can_read(1);
        map { $value = <$_> } @h;
        close $fd;
        chomp($value) if defined $value;
        $meta->{$lf} = $value =~ /^-?\d+(\.\d+)?$/ ? $value+0 : $value;
    }
    closedir $dh;
    return $meta;
}

sub get_license_count_type {
    my ($c, $type, $lic) = @_;

    return -1 if $c->config->{general}{ngcp_type} eq 'spce';

    my $proc_dir = '/proc/ngcp';
    unless (-d $proc_dir) {
        $c->log->error("Failed to access $proc_dir");
        return 0;
    };

    my $lic_file = $proc_dir . '/' . $type . '_' . $lic;
    return unless (-r $lic_file);

    sysopen(my $fd, "$lic_file", O_NONBLOCK|O_RDONLY) || do {
        $c->log->error("Failed to open license file $lic_file: $!");
        return 0;
    };
    my $value;
    my @h = IO::Select->new($fd)->can_read(1);
    map { $value = <$_> } @h;
    close $fd;
    chomp($value) if defined $value;

    return -1 if $value eq 'unlimited';

    return $value ? $value+0 : 0;
}

sub get_max_pbx_groups {
    my ($c) = @_;

    return get_license_count_type($c, 'max', 'pbx_groups');
}

sub get_max_pbx_subscribers {
    my ($c) = @_;

    return get_license_count_type($c, 'max', 'pbx_subscribers');
}

sub get_max_subscribers {
    my ($c) = @_;

    return get_license_count_type($c, 'max', 'subscribers');
}

sub get_current_pbx_groups {
    my ($c) = @_;

    return get_license_count_type($c, 'current', 'pbx_groups');
}

sub get_current_pbx_subscribers {
    my ($c) = @_;

    return get_license_count_type($c, 'current', 'pbx_subscribers');
}

sub get_current_subscribers {
    my ($c) = @_;

    return get_license_count_type($c, 'current', 'subscribers');
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
my $status = get_license_status($c, \$ext_status);

=head2 is_license_status

Takes a list of strings as argument list. Returns true or false if the license
status is one of the status names given in the argument list.

Example:
if (is_license_status($c, qw(missing error))) ...

=head2 is_license_error

Similar to is_license_status($c) but returns the status string instead of true if
the license status is one of the values given. If the argument list is empty, it
defaults to ('error').

Example:
if (my $status = is_license_error($c)) ...

=head1 AUTHOR

Richard Fuchs

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
