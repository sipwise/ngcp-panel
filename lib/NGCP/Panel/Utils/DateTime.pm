package NGCP::Panel::Utils::DateTime;

use strict;
use warnings;

use DateTime::Format::ISO8601;
use DateTime::Format::Strptime;
use DateTime;
use POSIX qw(floor fmod);
use Readonly qw();
use Time::HiRes; #prevent warning from Time::Warp
use Time::Warp qw();

 my $RFC_1123_FORMAT_PATTERN = '%a, %d %b %Y %T %Z';
 my $TIMEZONE_MAP = { map { $_ => 1; } DateTime::TimeZone->all_names };
 my $LOCAL_TZ = DateTime::TimeZone->new(name => 'local');

my $is_fake_time = 0;

sub is_valid_timezone_name {
    my ($tz, $all, $c, $allow_empty) = @_;
    if (!$tz && !$allow_empty) {
        return 0;
    }
    if ($c) {
        $tz = NGCP::Panel::Utils::DateTime::strip_empty_timezone_name($c, $tz);
        #we allow empty value to switch to the parent default
        if (!$tz) {
            return $allow_empty ? 1 : 0;
        }
    }
    if ($all) {
        return DateTime::TimeZone->is_valid_name($tz);
    } else {
        return 0 unless exists $TIMEZONE_MAP->{$tz};
        return 1;
    }
}

sub strip_empty_timezone_name {
    my ($c, $value) = @_;
    my $default_names =  join ('|', map {'^'.$_} ($c->loc('customer default'),$c->loc('reseller default'),$c->loc('default')));
    if ($value =~ /$default_names/i) {
        return '';
    }
    return $value;
}

sub get_default_timezone_name {
    my($c, $parent_owner_type, $parent_owner_id) = @_;
    $parent_owner_type //= '';
    my ($default_tz_data, $default_tz_data_rs);
    my $parent_tz_rs;
    my $noparentinfo = ($parent_owner_type eq 'noparentinfo');
    if ($parent_owner_type && !$noparentinfo) {
        if ($parent_owner_id) { 
            if ($parent_owner_type eq 'contract') {
                $parent_tz_rs   = $c->model('DB')->resultset('contract_timezone')->search_rs({
                    'contract_id' => $parent_owner_id
                },{
                    'columns' => [ { name   => \('concat("'.$c->loc('customer default').' (",name,")")')} ],
                });
            } elsif ($parent_owner_type eq 'reseller') {
                $parent_tz_rs   = $c->model('DB')->resultset('reseller_timezone')->search_rs({
                    'reseller_id' => $parent_owner_id 
                },{
                    'columns' => [ { name   => \('concat("'.$c->loc('reseller default').' (",name,")")')} ],
                });
            }
        } elsif ($parent_owner_type eq 'top') {
            $default_tz_data = { name => $c->loc('default (localtime)') };
        } else {
            $default_tz_data = { name => $c->loc('default (parent/localtime)') };
        }
    } elsif ($noparentinfo) {
        $default_tz_data = { name => $c->loc('default (parent/localtime)') };
    }
    if (!$default_tz_data) {
        if ($parent_tz_rs) {
            $default_tz_data = { $parent_tz_rs->first->get_inflated_columns };
        } else {
            $default_tz_data = { name => $c->loc('default (parent/localtime)') };
        }
    }
    return  $default_tz_data;
}

sub normalize_db_tz_name {
    my $tz = shift;
    if (defined $tz) {
        if (lc($tz) eq 'localtime') {
            $tz = 'local';
        } elsif (lc($tz) eq 'system') {
            $tz = 'local';
        } # else { ... additional cases
    }
    return $tz;
}

sub current_local {
    if ($is_fake_time) {
        return DateTime->from_epoch(epoch => Time::Warp::time,
            time_zone => $LOCAL_TZ,
        );
    } else {
        return DateTime->now(
            time_zone => $LOCAL_TZ,
        );
    }
}

sub current_local_hires {

    #If the epoch value is a floating-point value, it will be rounded to nearest microsecond.
    return DateTime->from_epoch( epoch => Time::HiRes::time,
        time_zone => $LOCAL_TZ,
    );

}

sub set_local_tz {
    my $dt = shift;
    if (defined $dt && ref $dt eq 'DateTime' && !is_infinite($dt)) {
        $dt->set_time_zone($LOCAL_TZ);
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

sub convert_tz {
    my ($dt,$from_tz,$to_tz,$c) = @_;
    #use Data::Dumper;
    #$c->log->debug("converting $dt from '". Dumper($from_tz) ."' to $to_tz'") if $c;
    $c->log->debug("converting $dt from '$from_tz' to '$to_tz'") if $c;
    $from_tz = 'local' if (not defined $from_tz or lc($from_tz) eq 'system');
    $to_tz = 'local' if (not defined $to_tz or lc($to_tz) eq 'system');
    $dt = $dt->clone; #do not touch the original
    return $dt if (is_infinite($dt) or $from_tz eq $to_tz);
    my $tz = $dt->time_zone; #save away the original tz the dt was marked with
    $dt->set_time_zone("floating") unless $tz->is_floating;; #unmark
    $dt->set_time_zone($from_tz); #set "from" tz
    $dt->set_time_zone($to_tz); #convert to "to" tz
    $dt->set_time_zone("floating"); #unmark
    $dt->set_time_zone($tz) unless $tz->is_floating; #mark again with the original tz
    return $dt;
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
        time_zone => $LOCAL_TZ,
        epoch => $epoch,
    );
}

sub epoch_tz {
    my ($epoch, $tz) = @_;
    #if(!$tz || !DateTime::TimeZone->is_valid_name($tz)) {
    if(not is_valid_timezone_name($tz,1)) {
        $tz = $LOCAL_TZ;
    }
    return DateTime->from_epoch(
        time_zone => $tz,
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

sub from_mysql_to_js{
    my $s = shift;
    $s =~ s/^(\d{4}\-\d{2}\-\d{2})T(\d.+)$/$1 $2/;
    return $s;
  
}

sub from_rfc1123_string {

    my $s = shift;
    my $strp = DateTime::Format::Strptime->new(pattern => $RFC_1123_FORMAT_PATTERN,
       locale => 'en_US',
       on_error => 'undef');
    return $strp->parse_datetime($s);
}

# this shall give a little freedom in how datetime is entered
# this shall be allowed: Y-m-d H:M:S, Y-m-d H:M, Y-m-d
# it returns a DateTime object in floating (meaning local) timezone or the specified timezone
sub from_forminput_string {
    my($string, $tz) = @_;
    $string =~ s/^\s*(.*)\s*$/$1/; # remove whitespace around
    $string =~ s/T/ /; # replace T from API input
    my ($dt);
    foreach my $pattern ('%Y-%m-%d %H:%M:%S','%Y-%m-%d %H:%M','%Y-%m-%d') {
        my $parser = DateTime::Format::Strptime->new(
            pattern => $pattern,
            $tz ? (time_zone => $tz) : (),
        );
        $dt = $parser->parse_datetime($string);
        last if $dt;
    }
    return $dt;
}

sub new_local {
    my %params;
    @params{qw/year month day hour minute second nanosecond/} = @_;
    foreach(keys %params){
        defined($params{$_}) or delete($params{$_});
    }
    return DateTime->new(
        time_zone => $LOCAL_TZ,
        %params,
    );
}

# convert seconds to 'HH:MM:SS.x' format
sub sec_to_hms {
    my ($c,$secs,$sec_decimals) = @_;
    $sec_decimals //= 0;
    my ($result,$years,$months,$days,$hours,$minutes,$seconds) = to_duration_string($c,$secs,'hours','seconds',$sec_decimals);
    $result = sprintf("%d", $hours) . ':' . sprintf("%02d", $minutes) . ':' . sprintf("%02d", $seconds);
    my $fractional_secs;
    if ($sec_decimals > 0 && ($fractional_secs = $seconds - int($seconds)) > 0.0) {
        $result .= '.' . substr(sprintf('%.' . $sec_decimals . 'f', $fractional_secs),2);
    }
    return $result;
}

sub to_string {
    my ($dt) = @_;
    return unless defined ($dt);
    my $s = $dt->ymd('-') . ' ' . $dt->hms(':');
    $s .= '.'.sprintf("%03d",$dt->millisecond) if $dt->millisecond > 0.0;
    return $s;
}

sub to_rfc1123_string {
    my $dt = shift;
    my $strp = DateTime::Format::Strptime->new(pattern => $RFC_1123_FORMAT_PATTERN,
       locale => 'en_US',
       on_error => 'undef');
    return $strp->format_datetime($dt);
}

sub to_local_string {
    my ($dt) = @_;

    unless ('DateTime' eq ref $dt) {
        die 'needs a DateTime object to be converted';
    }

    $dt->set_time_zone($LOCAL_TZ);
    return to_string($dt);
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

#pretty printing a duration given in seconds according to ISO8601v2000, Section 5.5.3.2:
sub to_duration_string {
    my ($c,$duration_secs,$most_significant,$least_significant,$least_significant_decimals) = @_;
    my $abs = abs($duration_secs);
    my ($years,$months,$days,$hours,$minutes,$seconds);
    my $result = '';
    if ('seconds' ne $least_significant) {
        $abs = $abs / 60.0; #minutes
        if ('minutes' ne $least_significant) {
            $abs = $abs / 60.0; #hours
            if ('hours' ne $least_significant) {
                $abs = $abs / 24.0; #days
                if ('days' ne $least_significant) {
                    $abs = $abs / 30.0; #months
                    if ('months' ne $least_significant) {
                        $abs = $abs / 12.0; #years
                        if ('years' ne $least_significant) {
                            die("unknown least significant duration unit-of-time: '$least_significant'");
                        } else {
                            $seconds = 0.0;
                            $minutes = 0.0;
                            $hours = 0.0;
                            $days = 0.0;
                            $months = 0.0;
                            if ('years' eq $most_significant) {
                                $years = $abs;
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    } else {
                        $seconds = 0.0;
                        $minutes = 0.0;
                        $hours = 0.0;
                        $days = 0.0;
                        $years = 0.0;
                        if ('months' eq $most_significant) {
                            $months = $abs;
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                } else {
                    $seconds = 0.0;
                    $minutes = 0.0;
                    $hours = 0.0;
                    $months = 0.0;
                    $years = 0.0;
                    if ('days' eq $most_significant) {
                        $days = $abs;
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30.0) : $abs;
                        $abs = $abs / 30.0;
                        if ('months' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            } else {
                $seconds = 0.0;
                $minutes = 0.0;
                $days = 0.0;
                $months = 0.0;
                $years = 0.0;
                if ('hours' eq $most_significant) {
                    $hours = $abs;
                } else {
                    $hours = ($abs >= 24.0) ? fmod($abs,24.0) : $abs;
                    $abs = $abs / 24.0;
                    if ('days' eq $most_significant) {
                        $days = floor($abs);
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30) : $abs;
                        $abs = $abs / 30.0;
                        if ('months' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            }
        } else {
            $seconds = 0.0;
            $hours = 0.0;
            $days = 0.0;
            $months = 0.0;
            $years = 0.0;
            if ('minutes' eq $most_significant) {
                $minutes = $abs;
            } else {
                $minutes = ($abs >= 60.0) ? fmod($abs,60.0) : $abs;
                $abs = $abs / 60.0;
                if ('hours' eq $most_significant) {
                    $hours = floor($abs);
                } else {
                    $hours = ($abs >= 24.0) ? fmod($abs,24.0) : $abs;
                    $abs = $abs / 24.0;
                    if ('days' eq $most_significant) {
                        $days = floor($abs);
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30.0) : $abs;
                        $abs = $abs / 30.0;
                        if ('months' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            }
        }
    } else {
        $minutes = 0.0;
        $hours = 0.0;
        $days = 0.0;
        $months = 0.0;
        $years = 0.0;
        if ('seconds' eq $most_significant) {
            $seconds = $abs;
        } else {
            $seconds = ($abs >= 60.0) ? fmod($abs,60.0) : $abs;
            $abs = $abs / 60.0;
            if ('minutes' eq $most_significant) {
                $minutes = floor($abs);
            } else {
                $minutes = ($abs >= 60.0) ? fmod($abs,60.0) : $abs;
                $abs = $abs / 60.0;
                if ('hours' eq $most_significant) {
                    $hours = floor($abs);
                } else {
                    $hours = ($abs >= 24.0) ? fmod($abs,24.0) : $abs;
                    $abs = $abs / 24.0;
                    if ('days' eq $most_significant) {
                        $days = floor($abs);
                    } else {
                        $days = ($abs >= 30.0) ? fmod($abs,30.0) : $abs;
                        $abs = $abs / 30.0;
                        if ('minutes' eq $most_significant) {
                            $months = floor($abs);
                        } else {
                            $months = ($abs >= 12.0) ? fmod($abs,12.0) : $abs;
                            $abs = $abs / 12.0;
                            if ('years' eq $most_significant) {
                                $years = floor($abs);
                            } else {
                                die("most significant duration unit-of-time '$most_significant' lower than least significant duration unit-of-time '$least_significant'");
                            }
                        }
                    }
                }
            }
        }
    }
    if ($years > 0.0) {
        if ($months > 0.0 || $days > 0.0 || $hours > 0.0 || $minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($c,$years, 0, 'years');
        } else {
            $result .= _duration_unit_of_time_value_to_string($c,$years, $least_significant_decimals, 'years');
        }
    }
    if ($months > 0.0) {
        if ($years > 0.0) {
            $result .= ', ';
        }
        if ($days > 0.0 || $hours > 0.0 || $minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($c,$months, 0, 'months');
        } else {
            $result .= _duration_unit_of_time_value_to_string($c,$months, $least_significant_decimals, 'months');
        }
    }
    if ($days > 0.0) {
        if ($years > 0.0 || $months > 0.0) {
            $result .= ', ';
        }
        if ($hours > 0.0 || $minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($c,$days, 0, 'days');
        } else {
            $result .= _duration_unit_of_time_value_to_string($c,$days, $least_significant_decimals, 'days');
        }
    }
    if ($hours > 0.0) {
        if ($years > 0.0 || $months > 0.0 || $days > 0.0) {
            $result .= ', ';
        }
        if ($minutes > 0.0 || $seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($c,$hours, 0, 'hours');
        } else {
            $result .= _duration_unit_of_time_value_to_string($c,$hours, $least_significant_decimals, 'hours');
        }
    }
    if ($minutes > 0.0) {
        if ($years > 0.0 || $months > 0.0 || $days > 0.0 || $hours > 0.0) {
            $result .= ', ';
        }
        if ($seconds > 0.0) {
            $result .= _duration_unit_of_time_value_to_string($c,$minutes, 0, 'minutes');
        } else {
            $result .= _duration_unit_of_time_value_to_string($c,$minutes, $least_significant_decimals, 'minutes');
        }
    }
    if ($seconds > 0.0) {
        if ($years > 0.0 || $months > 0.0 || $days > 0.0 || $hours > 0.0 || $minutes > 0.0) {
            $result .= ', ';
        }
        $result .= _duration_unit_of_time_value_to_string($c,$seconds, $least_significant_decimals, 'seconds');
    }
    if (length($result) == 0) {
        $result .= _duration_unit_of_time_value_to_string($c,0.0, $least_significant_decimals, $least_significant);
    }
    return ($result,$years,$months,$days,$hours,$minutes,$seconds);
}

sub _duration_unit_of_time_value_to_string {
    my ($c,$value, $decimals, $unit_of_time) = @_;
    my $result = '';
    my $unit_label_plural = '';
    my $unit_label_singular = '';
    if (defined $c) {
        if ('seconds' eq $unit_of_time) {
            $unit_label_plural = ' ' . $c->loc('seconds');
            $unit_label_singular = ' ' . $c->loc("second");
        } elsif ('minutes' eq $unit_of_time) {
            $unit_label_plural = ' ' . $c->loc('minutes');
            $unit_label_singular = ' ' . $c->loc("minute");
        } elsif ('hours' eq $unit_of_time) {
            $unit_label_plural = ' ' . $c->loc('hours');
            $unit_label_singular = ' ' . $c->loc("hour");
        } elsif ('days' eq $unit_of_time) {
            $unit_label_plural = ' ' . $c->loc('days');
            $unit_label_singular = ' ' . $c->loc("day");
        } elsif ('months' eq $unit_of_time) {
            $unit_label_plural = ' ' . $c->loc('months');
            $unit_label_singular = ' ' . $c->loc("month");
        } elsif ('years' eq $unit_of_time) {
            $unit_label_plural = ' ' . $c->loc('years');
            $unit_label_singular = ' ' . $c->loc("year");
        }
    }
    if ($decimals < 1) {
        if (int($value) == 1) {
            $result .= '1';
            $result .= $unit_label_singular;
        } else {
            $result .= int($value);
            $result .= $unit_label_plural;
        }
    } else {
        $result .= sprintf('%.' . $decimals . 'f', $value);
        $result .= $unit_label_plural;
    }
    return $result;
}

1;

# vim: set tabstop=4 expandtab:
