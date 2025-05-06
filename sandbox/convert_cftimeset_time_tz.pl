use strict;
use warnings;

use DateTime qw();
use DateTime::TimeZone qw();

eval 'use lib "/home/rkrenn/sipwise/git/ngcp-schema/lib";';
eval 'use lib "/home/rkrenn/sipwise/git/sipwise-base/lib";';
eval 'use NGCP::Schema;';

my $schema = undef;
if ($@) {
    die('failed to load NGCP::Schema: ' . $@);
} else {
    print "connecting to ngcp db";
    $schema = NGCP::Schema->connect({
        dsn                 => "DBI:mysql:database=provisioning;host=192.168.0.29;port=3306",
        user                => "root",
        #password            => "...",
        mysql_enable_utf8   => "1",
        on_connect_do       => "SET NAMES utf8mb4",
        quote_char          => "`",
    });
}

goto WRITE_TO_DB;

print "\n" . process_file('/home/rkrenn/temp/cftimeset_tz/cftimesets.txt',sub { #'/home/rkrenn/temp/cftimeset_tz/cftimesets.txt'
    my $item = shift;
    my @times;
    print "\nsubscriber id $item->{subscriber_id} - $item->{timezone}: ";
    for my $timeelem (@{$item->{voip_cf_periods}}) {
        delete $timeelem->{'id'};
        push @times, $timeelem;
    }

    my $converted_times = apply_owner_timezone(
        undef,
        \@times,
        'inflate',
        $item->{timezone},
    );

    if ($converted_times) {
        #use Data::Dumper;
        #print Dumper($converted_times);
        my $indent = 40;
        for (my $i = 0; $i < ((scalar @{$item->{voip_cf_periods}} > scalar @$converted_times) ? scalar @{$item->{voip_cf_periods}} : scalar @$converted_times); $i++) {
            my $old = $item->{voip_cf_periods}->[$i];
            my $new = $converted_times->[$i];
            my $str = '';
            $str .= ' ' x $indent unless $old;
            $str = print_item($old,'time_set_id',$str);
            $str = print_item($old,'year',$str);
            $str = print_item($old,'month',$str);
            $str = print_item($old,'mday',$str);
            $str = print_item($old,'wday',$str);
            $str = print_item($old,'hour',$str);
            $str = print_item($old,'minute',$str);
            if ($new) {
                $str .= ' ' x ($indent-length($str));
                $str = print_item($new,'time_set_id',$str,1);
                $str = print_item($new,'year',$str);
                $str = print_item($new,'month',$str);
                $str = print_item($new,'mday',$str);
                $str = print_item($new,'wday',$str);
                $str = print_item($new,'hour',$str);
                $str = print_item($new,'minute',$str);
            }
            print $str . "\n";
        }
        return 1;
    } else {
        return 0;
    }
}) . ' rows processed';

WRITE_TO_DB:
print "\n" . process_rows('voip_cf_time_sets', sub {
    my $item = shift;
    my @times;

    my $tz = $schema->resultset('voip_subscriber_timezone')->search_rs({
            subscriber_id => $item->subscriber->voip_subscriber->id
        })->first;
    my $tz_name = normalize_db_tz_name($tz->name) if $tz;
    print "\nsubscriber id " . $item->subscriber->voip_subscriber->id . " - $tz_name: ";

    for my $time ($item->voip_cf_periods->all) {
        my $timeelem = {$time->get_inflated_columns};
        delete $timeelem->{'id'};
        push @times, $timeelem;
    }

    my $converted_times = apply_owner_timezone(
        $item->subscriber->voip_subscriber->id,
        \@times,
        'inflate',
    );

    if ($converted_times) {
        #use Data::Dumper;
        #print Dumper($converted_times);

        $item->voip_cf_periods->delete;
        for my $t ( @$converted_times ) {
            delete $t->{time_set_id};
            $item->create_related("voip_cf_periods", $t);
        }

        my $indent = 40;
        for (my $i = 0; $i < ((scalar @times > scalar @$converted_times) ? scalar @times : scalar @$converted_times); $i++) {
            my $old = $times[$i];
            my $new = $converted_times->[$i];
            my $str = '';
            $str .= ' ' x $indent unless $old;
            #$str = print_item($old,'time_set_id',$str);
            $str = print_item($old,'year',$str);
            $str = print_item($old,'month',$str);
            $str = print_item($old,'mday',$str);
            $str = print_item($old,'wday',$str);
            $str = print_item($old,'hour',$str);
            $str = print_item($old,'minute',$str);
            if ($new) {
                $str .= ' ' x ($indent-length($str));
                #$str = print_item($new,'time_set_id',$str,1);
                $str = print_item($new,'year',$str,1);
                $str = print_item($new,'month',$str);
                $str = print_item($new,'mday',$str);
                $str = print_item($new,'wday',$str);
                $str = print_item($new,'hour',$str);
                $str = print_item($new,'minute',$str);
            }
            print $str . "\n";
        }

        return 1;
    } else {
        return 0;
    }
}) . ' rows processed';
exit;

sub apply_owner_timezone {

    my ($subscriber_id, $times, $mode, $timezone) = @_;

    my $tz_name;
    if($timezone) {
        if (DateTime::TimeZone->is_valid_name($timezone)) {
            $tz_name = $timezone;
        } else {
            warn("timezone '$timezone' is not a valid time zone");
            return;
        }
    } elsif ($subscriber_id) {
        my $tz = $schema->resultset('voip_subscriber_timezone')->search_rs({
            subscriber_id => $subscriber_id
        })->first;
        $tz_name = normalize_db_tz_name($tz->name) if $tz;
    }
    $times //= [];
    my $tz_local = DateTime::TimeZone->new(name => 'local');
    my ($tz,$offset);
    if ($tz_name
        and ($tz = DateTime::TimeZone->new(name => $tz_name))
        and abs($offset = $tz->offset_for_datetime(DateTime->now()) - $tz_local->offset_for_datetime(DateTime->now())) > 0) {
        #print current_local()->hms;
        my $offset_hrs = int($offset / 3600.0);
        if ($offset_hrs * 3600 != $offset) {
            warn("only full hours supported for timezone offset ($tz_name: $offset seconds = $offset_hrs hours)");
            return;
        }

        #foreach my $time (@$times) {
        #    foreach $field (qw(year month mday) {
        #        if (exists $time->{$field} and $time->{$field}) {
        #            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "cannot apply a timezone offset for time with '$field' field ($time->{$field})");
        #            return;
        #        }
        #    }
        #}

        my $merge = 0;
        if ('deflate' eq $mode) { #for writing to db
            $offset_hrs = $offset_hrs * -1;
            print "cf timeset $mode for timezone $tz_name: offset $offset_hrs hours\n";
        } elsif ('inflate' eq $mode) { #for reading from db
            $merge = 1;
            print "cf timeset $mode for timezone $tz_name: offset $offset_hrs hours\n";
        } else {
            die("invalid mode $mode");
        }

        my ($yearmonthmday_map,$yearmonthmdays) = array_to_map($times,sub { my $time = shift;
            return (length($time->{year}) > 0 ? $time->{year} : '*') .
            '_' . ($time->{month} || '*') . '_' . ($time->{mday} || '*');
        },undef,'group');

        $times = [];
        foreach my $yearmonthmday (@$yearmonthmdays) {
            if ($offset_hrs > 0) {
                push(@$times,@{add($yearmonthmday_map->{$yearmonthmday},$offset_hrs,$merge)});
            } else {
                push(@$times,@{subtract($yearmonthmday_map->{$yearmonthmday},$offset_hrs,$merge)});
            }
        }

    } else {
        print "no timezone to convert to, or zero tz offset\n";
    }
    return $times;

}

sub process_rows {
    my ($relation,$code) = @_;

    my $item_rs = $schema->resultset($relation);
    my $page = 1;
    my $count = 0;
    while (my @page = $item_rs->search_rs(undef,{
        page => $page,
        rows => 100,
    })->all) {
        foreach my $item (@page) {
            if (&$code($item)) {
                $count++;
            }
        }
        $page++;
    }
    return $count;
}

sub process_file {
    my ($filename,$code) = @_;
    open(my $fh, '<:encoding(UTF-8)', $filename) or die "Could not open file '$filename' $!";
    my @rows = ();
    while (my $row = <$fh>) {
        my @cleaned = map {
            my $col = $_;
            $col =~ s/NULL//g;
            $col =~ s/[\r\n]//gi;
            length $col > 0 ? $col : undef;
        } split /,/, $row;
        push(@rows,{
            id => $cleaned[0],
            time_set_id => $cleaned[1],
            year => $cleaned[2],
            month => $cleaned[3],
            mday => $cleaned[4],
            wday => $cleaned[5],
            hour => $cleaned[6],
            minute => $cleaned[7],
            subscriber_id => $cleaned[8],
            timezone => $cleaned[9],
        });
    }
    close $fh;
    my ($map,$ids) = array_to_map(\@rows,sub {
        return shift->{time_set_id};
    },undef,'group');
    my $count = 0;
    foreach my $time_set_id (sort @$ids) {
        my $item = { voip_cf_periods => [] };
        foreach my $row (@{$map->{$time_set_id}}) {
            my $period = { %$row };
            $item->{subscriber_id} = delete $period->{subscriber_id};
            $item->{timezone} = delete $period->{timezone};
            push(@{$item->{voip_cf_periods}},$period);
        }
        if (&$code($item)) {
            $count++;
        }
    }
    return $count;
}

sub add {
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

sub subtract {
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
    return ($merge ? merge_adjacent(\@result) : \@result);

}

sub merge_adjacent {
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
    return DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local'),
    );
}

sub print_item {
    my ($item,$field,$str,$no_sep) = @_;
    if ($item) {
        $str .= ',' if (length($str) > 0 and not $no_sep);
        $str .= ($item->{$field} // 'NULL');
    }
    return $str;
}
