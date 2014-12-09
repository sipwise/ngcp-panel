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

    # if date is passed like xxxx-xx (as from monthpicker field), add a day
    $s = $s . "-01" if($s =~ /^\d{4}\-\d{2}$/);
    $s = $s . "T00:00:00" if($s =~ /^\d{4}\-\d{2}-\d{2}$/);

    # just for convenience, if date is passed like xxxx-xx-xx xx:xx:xx,
    # convert it to xxxx-xx-xxTxx:xx:xx
    $s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
    my $ts = DateTime::Format::ISO8601->parse_datetime($s);
    $ts->set_time_zone( DateTime::TimeZone->new(name => 'local') );
    return $ts;
}

sub new_local {
    my %params;
    @params{qw/year month day hour minute second nanosecond/} = @_;
    foreach(keys %params){
        !defined $params{$_} and delete $params{$_};
    }
    return DateTime->new(
        time_zone => DateTime::TimeZone->new(name => 'local'),
        %params,
    );
}

# convert seconds to 'HH:MM:SS' format
sub sec_to_hms
{
    use integer;
    local $_ = shift;
    my ($h, $m, $s);
    $s = sprintf("%02d", $_ % 60); $_ /= 60;
    $m = sprintf("%02d", $_ % 60); $_ /= 60;
    $h = $_;
    return "$h:$m:$s";
}


1;

# vim: set tabstop=4 expandtab:
