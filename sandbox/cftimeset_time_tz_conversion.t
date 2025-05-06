use strict;
use warnings;

use Test::More;

{
    use DateTime;
    use DateTime::TimeZone;
    my $tz = DateTime::TimeZone->new(name => 'America/Chicago'); #'Europe/Dublin');
    my $dt = DateTime->now();
    my $offset = $tz->offset_for_datetime($dt);
    diag($dt .' - offset: ' . $offset);
}

#goto SKIP;
### add
{
    # single day, no roll-over hours:
    is_deeply(_add([{wday => '7',hour => '2-3',},],3), [{wday => '7',hour => '5-6',
    },], "single day add, hour from and hour to not shifted to next day");
    is_deeply(_add([{wday => '7',hour => '20-23',},],3), [{wday => '7',hour => '23-23',},{wday => '1',hour => '0-2',
    }], "single day add, hour to shifted to next day");
    is_deeply(_add([{wday => '7',hour => '22-23',},],3), [{wday => '1',hour => '1-2',
    },], "single day add, hour from and hour to shifted to next day");

    # single day, roll over hours:
    is_deeply(_add([{wday => '7',hour => '3-2',},],3), [{wday => '7',hour => '6-5',
    },], "single day add, roll-over hour from and hour to not shifted to next day");
    is_deeply(_add([{wday => '7',hour => '22-3',},],3), [{wday => '1',hour => '1-6',
    },], "single day add, roll-over hour from shifted to next day");
    is_deeply(_add([{wday => '7',hour => '23-22',},],3), [{wday => '1',hour => '2-1',
    },], "single day add, roll-over hour from and hour to shifted to next day");

    # range days, no roll-over hours:
    is_deeply(_add([{wday => '3-7',hour => '2-3',},],3), [{wday => '3-7',hour => '5-6',
    },], "range days add, hour from and hour to not shifted to next day");
    is_deeply(_add([{wday => '3-7',hour => '20-23',},],3), [{wday => '3-7',hour => '23-23',},{wday => '4-1',hour => '0-2',
    }], "range days add, hour to shifted to next day");
    is_deeply(_add([{wday => '3-7',hour => '22-23',},],3), [{wday => '4-1',hour => '1-2',
    },], "range days add, hour from and hour to shifted to next day");

    # range days, roll over hours:
    is_deeply(_add([{wday => '3-7',hour => '3-2',},],3), [{wday => '3-7',hour => '6-5',
    },], "range days add, roll-over hour from and hour to not shifted to next day");
    is_deeply(_add([{wday => '3-7',hour => '22-3',},],3), [{wday => '4-1',hour => '1-6',
    },], "range days add, roll-over hour from shifted to next day");
    is_deeply(_add([{wday => '3-7',hour => '23-22',},],3), [{wday => '4-1',hour => '2-1',
    },], "range days add, roll-over hour from and hour to shifted to next day");

    # all days, no roll-over hours:
    is_deeply(_add([{wday => '7-1',hour => '2-3',},],3), [{wday => '7-1',hour => '5-6',
    },], "any days add, hour from and hour to not shifted to next day");
    is_deeply(_add([{wday => '1-7',hour => '20-23',},],3), [{wday => '1-7',hour => '23-23',},{wday => '1-7',hour => '0-2',
    }], "any days add, hour to shifted to next day");
    is_deeply(_add([{wday => '',hour => '22-23',},],3), [{wday => '',hour => '1-2',
    },], "any days add, hour from and hour to shifted to next day");

    # all days, roll over hours:
    is_deeply(_add([{wday => '7-1',hour => '3-2',},],3), [{wday => '7-1',hour => '6-5',
    },], "any days add, roll-over hour from and hour to not shifted to next day");
    is_deeply(_add([{wday => '',hour => '22-3',},],3), [{wday => '',hour => '1-6',
    },], "any days add, roll-over hour from shifted to next day");
    is_deeply(_add([{wday => '1-7',hour => '23-22',},],3), [{wday => '1-7',hour => '2-1',
    },], "any days add, roll-over hour from and hour to shifted to next day");

}

#SKIP:
### subtract
{
    # single day, no roll-over hours:
    is_deeply(_subtract([{wday => '1',hour => '5-6',},],3), [{wday => '1',hour => '2-3',
    },], "single day subtract, hour from and hour to not shifted to previous day");
    is_deeply(_subtract([{wday => '1',hour => '2-4',},],3), [{wday => '7',hour => '23-23',},{wday => '1',hour => '0-1',
    }], "single day subtract, hour from shifted to previous day");
    is_deeply(_subtract([{wday => '1',hour => '0-2',},],3), [{wday => '7',hour => '21-23',
    },], "single day subtract, hour from and hour to shifted to previous day");

    # single day, roll over hours:
    is_deeply(_subtract([{wday => '1',hour => '6-5',},],3), [{wday => '1',hour => '3-2',
    },], "single day subtract, roll-over hour from and hour to not shifted to previous day");
    is_deeply(_subtract([{wday => '1',hour => '6-1',},],3), [{wday => '7',hour => '3-22',
    },], "single day subtract, roll-over hour to shifted to previous day");
    is_deeply(_subtract([{wday => '1',hour => '2-1',},],3), [{wday => '7',hour => '23-22',
    },], "single day subtract, roll-over hour from and hour to shifted to previous day");

    # range days, no roll-over hours:
    is_deeply(_subtract([{wday => '1-3',hour => '5-6',},],3), [{wday => '1-3',hour => '2-3',
    },], "range days subtract, hour from and hour to not shifted to previous day");
    is_deeply(_subtract([{wday => '1-3',hour => '2-4',},],3), [{wday => '7-2',hour => '23-23',},{wday => '1-3',hour => '0-1',
    }], "range days subtract, hour from shifted to previous day");
    is_deeply(_subtract([{wday => '1-3',hour => '0-2',},],3), [{wday => '7-2',hour => '21-23',
    },], "range days subtract, hour from and hour to shifted to previous day");

    # range days, roll over hours:
    is_deeply(_subtract([{wday => '1-3',hour => '6-5',},],3), [{wday => '1-3',hour => '3-2',
    },], "range days subtract, roll-over hour from and hour to not shifted to previous day");
    is_deeply(_subtract([{wday => '1-3',hour => '6-1',},],3), [{wday => '7-2',hour => '3-22',
    },], "range days subtract, roll-over hour to shifted to previous day");
    is_deeply(_subtract([{wday => '1-3',hour => '2-1',},],3), [{wday => '7-2',hour => '23-22',
    },], "range days subtract, roll-over hour from and hour to shifted to previous day");

    # all days,  no roll-over hours:
    is_deeply(_subtract([{wday => '7-1',hour => '5-6',},],3), [{wday => '7-1',hour => '2-3',
    },], "any day subtract, hour from and hour to not shifted to previous day");
    is_deeply(_subtract([{wday => '1-7',hour => '2-4',},],3), [{wday => '1-7',hour => '23-23',},{wday => '1-7',hour => '0-1',
    }], "any day subtract, hour from shifted to previous day");
    is_deeply(_subtract([{wday => '',hour => '0-2',},],3), [{wday => '',hour => '21-23',
    },], "any day subtract, hour from and hour to shifted to previous day");

    # all days,  roll over hours:
    is_deeply(_subtract([{wday => '7-1',hour => '6-5',},],3), [{wday => '7-1',hour => '3-2',
    },], "any day subtract, roll-over hour from and hour to not shifted to previous day");
    is_deeply(_subtract([{wday => '1-7',hour => '6-1',},],3), [{wday => '1-7',hour => '3-22',
    },], "any day subtract, roll-over hour to shifted to previous day");
    is_deeply(_subtract([{wday => '',hour => '2-1',},],3), [{wday => '',hour => '23-22',
    },], "any day subtract, roll-over hour from and hour to shifted to previous day");
}

{
    is_deeply(_subtract(_add([{wday => '7',hour => '20-23',},],3),3,1), [{wday => '7',hour => '20-23',},],
    "merge adjacent add->subtract");
    is_deeply(_add(_subtract([{wday => '1',hour => '2-4',},],3),3,1), [{wday => '1',hour => '2-4',},],
    "merge adjacent subtract->add");
}

done_testing;

sub _add {
    my ($times,$offset_hrs,$merge) = @_;

    my @result = ();
    foreach my $time (@$times) {
        my $p1 = { %$time };
        unless (length($time->{hour}) > 0) {
            #nothing to do if there is no hour defined:
            push(@result,$p1);
            next;
        }
        my ($hour_start,$hour_end) = split(/\-/, $time->{hour});
        my $hour_range;
        if (defined $hour_end) {
            $hour_range = 1;
        } else {
            $hour_end = $hour_start;
            $hour_range = 0;
        }
        $hour_start += abs($offset_hrs);
        $hour_end += abs($offset_hrs);
        if ($hour_start < 24 and $hour_end < 24) {
            $p1->{hour} = ($hour_range ? $hour_start . '-' . $hour_end : $hour_start);
            push(@result,$p1);
            next;
        }
        my ($wday_start, $wday_end) = split(/\-/, $time->{wday} || '1-7');
        my $wday_range;
        if (defined $wday_end) {
            $wday_range = 1;
        } else {
            $wday_end = $wday_start;
            $wday_range = 0;
        }
        my @nums = ();
        if ($wday_start <= $wday_end) {
            push(@nums,$wday_start .. $wday_end);
        } else {
            push(@nums,$wday_start .. 7);
            push(@nums,1 .. $wday_end);
        }
        my ($p2,$p_shift_wday);
        if ($hour_start > 23 and $hour_end > 23) { #26-28
            $p1->{hour} = ($hour_range ? ($hour_start % 24) . '-' . ($hour_end % 24) : ($hour_start % 24)); #2-4
            $p_shift_wday = $p1;
        } elsif ($hour_start < $hour_end) {
            if ($hour_end > 23) { #17-23 +3-> 20-26
                $p1->{hour} = $hour_start . '-23'; #20-0
                $p2 = { %$time };
                $p2->{hour} = '0-' . ($hour_end % 24); #0-2
                $p_shift_wday = $p2;
            }
        } else {
            if ($hour_start > 23) { #23-17 +3-> 26-20
                $p1->{hour} = ($hour_start % 24) . '-' . $hour_end; #2-20
                $p_shift_wday = $p1;
            }
        }
        if ($p_shift_wday and (scalar @nums) < 7) {
            $p_shift_wday->{wday} = ($wday_range ? (($wday_start) % 7 + 1) . '-' . (($wday_end) % 7 + 1) : (($wday_start) % 7 + 1));
        }
        push(@result,$p1);
        push(@result,$p2) if $p2;
    }
    return ($merge ? merge_adjacent(\@result) : \@result);

}

sub _subtract {
    my ($times,$offset_hrs,$merge) = @_;

    my @result = ();
    foreach my $time (@$times) {
        my $p1 = { %$time };
        unless (length($time->{hour}) > 0) {
            #nothing to do if there is no hour defined:
            push(@result,$p1);
            next;
        }
        my ($hour_start,$hour_end) = split(/\-/, $time->{hour});
        my $hour_range;
        if (defined $hour_end) {
            $hour_range = 1;
        } else {
            $hour_end = $hour_start;
            $hour_range = 0;
        }
        $hour_start -= abs($offset_hrs);
        $hour_end -= abs($offset_hrs);
        if ($hour_start >= 0 and $hour_end >= 0) {
            $p1->{hour} = ($hour_range ? $hour_start . '-' . $hour_end : $hour_start);
            push(@result,$p1);
            next;
        }
        my ($wday_start, $wday_end) = split(/\-/, $time->{wday} || '1-7');
        my $wday_range;
        if (defined $wday_end) {
            $wday_range = 1;
        } else {
            $wday_end = $wday_start;
            $wday_range = 0;
        }
        my @nums = ();
        if ($wday_start <= $wday_end) {
            push(@nums,$wday_start .. $wday_end);
        } else {
            push(@nums,$wday_start .. 7);
            push(@nums,1 .. $wday_end);
        }
        my ($p2,$p_shift_wday);
        if ($hour_start < 0 and $hour_end < 0) { #-4 - -2
            $p1->{hour} = ($hour_range ? ($hour_start % 24) . '-' . ($hour_end % 24) : ($hour_start % 24)); #20-22
            $p_shift_wday = $p1;
        } elsif ($hour_start < $hour_end) { #-4 - 3
            if ($hour_start < 0) { #0-7 -4-> -4 - 3
                $p1->{hour} = ($hour_start % 24) . '-23'; #20-0
                $p2 = { %$time };
                $p2->{hour} = '0-' . $hour_end; #0-3
                $p_shift_wday = $p1;
            }
        } else {
            if ($hour_end < 0) { #22 - 2 -6-> 16 - -4
                $p1->{hour} = $hour_start . '-' . ($hour_end % 24); #16-20
                $p_shift_wday = $p1;
            }
        }
        if ($p_shift_wday and (scalar @nums) < 7) {
            $p_shift_wday->{wday} = ($wday_range ? (($wday_start - 2) % 7 + 1) . '-' . (($wday_end - 2) % 7 + 1) : (($wday_start - 2) % 7 + 1));
        }
        push(@result,$p1);
        push(@result,$p2) if $p2;
    }
    return ($merge ? _merge_adjacent(\@result) : \@result);

}

sub _merge_adjacent {
    my ($times) = @_;

    my ($wday_map,$wdays) = array_to_map($times,sub { my $time = shift;
        my $wday = $time->{wday} || '1-7';
        $wday = '1-7' if $time->{wday} eq '7-1';
        $wday .= '_' . (defined $time->{minute} ? $time->{minute} : '*');
        return $wday;
    },undef,'group');

    my @result = ();
    my $idx = 0;
    foreach my $wday (@$wdays) {
        my %hour_start_map = ();
        my %hour_end_map = ();
        my %skip_map = ();
        my $old_idx = $idx;
        foreach my $time (@{$wday_map->{$wday}}) {
            if (length($time->{hour}) > 0) {
                my ($hour_start,$hour_end) = split(/\-/, $time->{hour});
                $hour_end //= $hour_start;
                if ($hour_end >= $hour_start) { #we do not create any adjacent roll-over hours, so we also skip such when merging
                    if (not defined $hour_start_map{$hour_start}
                        or $hour_end > $hour_start_map{$hour_start}->{hour_end}) {
                        $hour_start_map{$hour_start} = { hour_end => $hour_end, idx => $idx, };
                    } else {
                        $skip_map{$idx} = 0;
                    }
                    if (not defined $hour_end_map{$hour_end}
                        or $hour_start < $hour_end_map{$hour_end}->{hour_start}) {
                        $hour_end_map{$hour_end} = { hour_start => $hour_start, }; #, idx => $idx,
                    } else {
                        $skip_map{$idx} = 0;
                    }
                } else {
                    $skip_map{$idx} = 1;
                }
            } else {
                $skip_map{$idx} = 1;
            }
            $idx++;
        }
        $idx = $old_idx;
        foreach my $time (@{$wday_map->{$wday}}) {
            my $p = { %$time };
            if (exists $skip_map{$idx}) {
                push(@result,$p) if $skip_map{$idx};
            } else {
                my ($hour_start,$hour_end) = split(/\-/, $time->{hour});
                $hour_end //= $hour_start;
                #if ($hour_end_map{$hour_end}->{idx} == $idx) {
                    my $adjacent_start = $hour_end + 1;
                    if (exists $hour_start_map{$adjacent_start}) {
                        $p->{hour} = $hour_start . '-' . $hour_start_map{$adjacent_start}->{hour_end};
                        $skip_map{$hour_start_map{$adjacent_start}->{idx}} = 0;
                    }
                    push(@result,$p);
                #}
            }
            $idx++;
        }
    }
    return \@result;
}

sub _merge {
    my ($times) = @_;

    my ($wday_map,$wdays,$wday_groups) = array_to_map($times,sub { my $time = shift;
        my $wday = $time->{wday} || '1-7';
        $wday = '1-7' if $time->{wday} eq '7-1';
        $wday .= '_' . (defined $time->{minute} ? $time->{minute} : '*');
        return $wday;
    },undef,'group');

    my @result = ();
    my %ranges = ();
    foreach my $wday (@$wdays) {
        foreach my $time (@{$wday_map->{$wday}}) {
            my $p = { %$time };
            if (length($time->{hour}) > 0) {
                my ($hour_start,$hour_end) = split(/\-/, $time->{hour});
                $hour_end //= $hour_start;
                if ($hour_end >= $hour_start) {
                    #https://stackoverflow.com/questions/42928964/finding-and-merging-down-intervalls-in-perl
                    my $in_range = 0;
                    foreach my $range (@{$ranges{$wday}} ) {
                        if (($hour_start >= $range->{start} and $hour_start <= $range->{end})
                             or ( $hour_end >= $range->{start} and $hour_end <= $range->{end})
                            ) {
                            $range->{end} = $hour_end if $hour_end > $range->{end};
                            $range->{start} = $hour_start if $hour_start < $range->{start};
                            $in_range++;
                        }
                    }
                    if (not $in_range) {
                        push(@{$ranges{$wday}},{ start => $hour_start, end => $hour_end, });
                        $p->{hour} = $hour_start . '-' . $hour_end;
                        push(@result,$p);
                    }
                } else { #splitting by the tz offset add/subtract never produces roll-overs, so we don't merge such
                    push(@result,$p);
                }
            } else {
                push(@result,$p);
            }
        }
    }
    return \@result;

}




sub array_to_map {

    my ($array_ptr,$get_key_code,$get_value_code,$mode) = @_;
    my $map = {};
    my @keys = ();
    my @values = ();
    if (defined $array_ptr and ref $array_ptr eq 'ARRAY') {
        if (defined $get_key_code and ref $get_key_code eq 'CODE') {
            if (not (defined $get_value_code and ref $get_value_code eq 'CODE')) {
                $get_value_code = sub { return shift; };
            }
            $mode = lc($mode);
            if (not ($mode eq 'group' or $mode eq 'first' or $mode eq 'last')) {
                $mode = 'group';
            }
            foreach my $item (@$array_ptr) {
                my $key = &$get_key_code($item);
                if (defined $key) {
                    my $value = &$get_value_code($item);
                    if (defined $value) {
                        if (not exists $map->{$key}) {
                            if ($mode eq 'group') {
                                $map->{$key} = [ $value ];
                            } else {
                                $map->{$key} = $value;
                            }
                            push(@keys,$key);
                        } else {
                            if ($mode eq 'group') {
                                push(@{$map->{$key}}, $value);
                            } elsif ($mode eq 'last') {
                                $map->{$key} = $value;
                            }
                        }
                        push(@values,$value);
                    }
                }
            }
        }
    }
    return ($map,\@keys,\@values);

}