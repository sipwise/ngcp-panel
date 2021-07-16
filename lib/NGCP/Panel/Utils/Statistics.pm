package NGCP::Panel::Utils::Statistics;
use strict;
use warnings;

use DateTime::TimeZone::OffsetOnly;
use File::Find::Rule;
use File::Slurp qw(read_file);
use POSIX;
use Time::Local;

sub tz_offset {
    use DateTime::TimeZone::OffsetOnly;
    my $tz_offset = DateTime::TimeZone::OffsetOnly->new(
        offset => strftime("%z", localtime(time())) 
    );
    return $tz_offset->{offset};
}

sub get_dpkg_versions {
    my ($self) = @_;
    return `LANG=C dpkg-query -f '\${db:Status-Abbrev} \${Package} \${Version}\\n' -W 2>/dev/null`;
}

sub get_dpkg_support_status {
    my ($self) = @_;
    my $packages = `LANG=C dpkg-query -l 'ngcp-support*' 2>/dev/null | grep 'ii \\+ngcp-support-\\(\\|no\\)access' 2>/dev/null`;
    if ($packages =~ m/ngcp-support-access/i) {
        return 1;
    } elsif ($packages =~ m/ngcp-support-noaccess/i) {
        return 2;
    } else {
        return 3;
    }
}

sub has_ngcp_status {
    my $self = shift;

    return -x '/usr/sbin/ngcp-collective-check';
}

sub get_ngcp_status {
    my ($self) = @_;
    return `/usr/sbin/ngcp-collective-check json`;
}

1;

# vim: set tabstop=4 expandtab:
