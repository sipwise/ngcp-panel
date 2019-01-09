use strict;

my $times = [{

},{

}];

sub add {
    my ($times,$offset_hrs);

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
                $p1->{hour} = $hour_start . '-0'; #20-0
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
    return \@result;

}

sub subtract {
    my ($times,$offset_hrs);

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
                $p1->{hour} = ($hour_start % 24) . '-0'; #20-0
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
    return \@result;

}