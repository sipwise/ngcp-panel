package NGCP::Panel::Utils::DateTime;

#use Sipwise::Base; seg fault when creating threads in test scripts
use strict;
use warnings;
use Time::HiRes; #prevent warning from Time::Warp
use Time::Warp qw();
#use Time::Fake; #load this before any use DateTime
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::Strptime;

use constant RFC_1123_FORMAT_PATTERN => '%a, %d %b %Y %T %Z';

my $is_fake_time = 0;

sub current_local {
    if ($is_fake_time) {
        return DateTime->from_epoch(epoch => Time::Warp::time,
            time_zone => DateTime::TimeZone->new(name => 'local')
        );
    } else {
        return DateTime->now(
            time_zone => DateTime::TimeZone->new(name => 'local')
        );
    }
}

sub set_local_tz {
    my $dt = shift;
    if (defined $dt && ref $dt eq 'DateTime' && !is_infinite($dt)) {
        $dt->set_time_zone('local');
    }
    return $dt;
}

sub infinite_past {
    #mysql 5.5: The supported range is '1000-01-01 00:00:00' ...
    return DateTime->new(year => 1000, month => 1, day => 1, hour => 0, minute => 0, second => 0,
        time_zone => DateTime::TimeZone->new(name => 'UTC')
    );
    #$dt->epoch calls should be okay if perl >= 5.12.0
}

sub is_infinite_past {
    my $dt = shift;
    return $dt->year <= 1000;
}

sub infinite_future {
    #... to '9999-12-31 23:59:59'
    return DateTime->new(year => 9999, month => 12, day => 31, hour => 23, minute => 59, second => 59,
        #applying the 'local' timezone takes too long -> "The current implementation of DateTime::TimeZone
        #will use a huge amount of memory calculating all the DST changes from now until the future date.
        #Use UTC or the floating time zone and you will be safe."
        time_zone => DateTime::TimeZone->new(name => 'UTC')
        #- with floating timezones, the long conversion takes place when comparing with a 'local' dt
        #- the error due to leap years/seconds is not relevant in comparisons
    );
}

sub is_infinite_future {
    my $dt = shift;
    return $dt->year >= 9999;
}

sub is_infinite {
    my $dt = shift;
    return is_infinite_future($dt) || is_infinite_past($dt);
}

sub set_fake_time {
    my ($o) = @_;
    $is_fake_time = 1;
    if (defined $o) {
        if (ref $o eq 'DateTime') {
            $o = $o->epoch;
        } else {
            my %mult = (
                s => 1,
                m => 60,
                h => 60*60,
                d => 60*60*24,
                M => 60*60*24*30,
                y => 60*60*24*365,
            );

            if (!$o) {
                $o = time;
            } elsif ($o =~ m/^([+-]\d+)([smhdMy]?)$/) {
                $o = time + $1 * $mult{ $2 || "s" };
            } elsif ($o !~ m/\D/) {

            } else {
                die("Invalid time offset: '$o'");
            }
        }
        Time::Warp::to($o);
    } else {
        Time::Warp::reset();
    }
}

sub last_day_of_month {
    my $dt = shift;
    return DateTime->last_day_of_month(year => $dt->year, month => $dt->month,
                                       time_zone => DateTime::TimeZone->new(name => 'local'))->day;
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

sub from_rfc1123_string {

    my $s = shift;

    my $strp = DateTime::Format::Strptime->new(pattern => RFC_1123_FORMAT_PATTERN,
                                               locale => 'en_US',
                                               on_error => 'undef');

    return $strp->parse_datetime($s);

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

sub to_string
{
    my ($dt) = @_;
    return unless defined ($dt);
    my $s = $dt->ymd('-') . ' ' . $dt->hms(':');
    $s .= '.'.$dt->millisecond if $dt->millisecond > 0.0;
    return $s;
}

sub to_rfc1123_string {

    my $dt = shift;

    my $strp = DateTime::Format::Strptime->new(pattern => RFC_1123_FORMAT_PATTERN,
                                               locale => 'en_US',
                                               on_error => 'undef');

    return $strp->format_datetime($dt);

}

sub get_weekday_names {
    my $c = shift;
    return [
            $c->loc('Monday'),
            $c->loc('Tuesday'),
            $c->loc('Wednesday'),
            $c->loc('Thursday'),
            $c->loc('Friday'),
            $c->loc('Saturday'),
            $c->loc('Sunday')
        ];
}

1;

# vim: set tabstop=4 expandtab:
