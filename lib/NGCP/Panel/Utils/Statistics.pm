package NGCP::Panel::Utils::Statistics;
use strict;
use warnings;

use DateTime::TimeZone::OffsetOnly;
use Time::Local;
use POSIX;
use File::Find::Rule;
use List::MoreUtils qw(apply);

sub tz_offset {
    use DateTime::TimeZone::OffsetOnly;
    my $tz_offset = DateTime::TimeZone::OffsetOnly->new(
        offset => strftime("%z", localtime(time())) 
    );
    return $tz_offset->{offset};
}

sub get_host_list {
    my @hosts = File::Find::Rule->directory
                    ->mindepth( 1 )
                    ->maxdepth( 1 )
                    ->in('/var/lib/collectd/rrd');
    @hosts = sort {$a cmp $b} apply { s|.*/|| } @hosts;
    return \@hosts;
}

sub get_host_subdirs {
    my ($host) = @_;

    my $rule = File::Find::Rule->extras({ follow => 1 });
    my @dirs = $rule->directory
                    ->mindepth( 1 )
                    ->maxdepth( 1 )
                    ->in('/var/lib/collectd/rrd/' . $host);
    @dirs = sort {$a cmp $b} apply { s|.*/|| } @dirs;
    return \@dirs;
}

sub get_rrd_files {
    my($host, $folder) = @_;

    my @rrds = File::Find::Rule->file
                    ->mindepth( 1 )
                    ->maxdepth( 1 )
                    ->in('/var/lib/collectd/rrd/' . $host . '/' . $folder);
    @rrds = sort {$a cmp $b} apply { s|.*/|| } @rrds;
    return \@rrds;
}

sub get_rrd {
    my ($path) = @_;

    my $content = "";

    my $fullpath = '/var/lib/collectd/rrd/' . $path;
    open(my $RRD, "<", $fullpath) or return; # TODO: error
    binmode($RRD) or return; # TODO: error
    my ($buffer, $r);
    do {
        $r = read($RRD, $buffer, 1024);
        unless(defined($r)) {
            close($RRD);
            return; # TODO: error
        }
        $content .= $buffer;
    } while($r > 0);
    close($RRD);
    return $content;
}

1;

# vim: set tabstop=4 expandtab:
