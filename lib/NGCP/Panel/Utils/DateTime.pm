package NGCP::Panel::Utils::DateTime;

use Sipwise::Base;
use DateTime;
use DateTime::Format::ISO8601;

sub current_local {
    return DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
}

sub epoch_local {
    my $epoch = shift;
    return DateTime->from_epoch(
        time_zone => DateTime::TimeZone->new(name => 'local'),
        epoch => $epoch,
    );
}

sub from_string {
    my $s = shift;
    # just for convenience, if date is passed like xxxx-xx-xx xx:xx:xx,
    # convert it to xxxx-xx-xxTxx:xx:xx
    $s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
    my $ts = DateTime::Format::ISO8601->parse_datetime($s);
    return $ts;
}

1;

# vim: set tabstop=4 expandtab:
