#!/usr/bin/perl
use strict;
use LWP::UserAgent qw();
use JSON qw();
use DateTime qw();
use DateTime::Format::Strptime qw();
use DateTime::Format::ISO8601 qw();
use Getopt::Long;

my $host = '127.0.0.1';
my $port = 443;
my $user = 'administrator';
my $pass = 'administrator';
my $output_dir = '';
my $output_filename;
my $verbose = 0;
my $period = '';

my $print_colnames = 1;
my $linebreak = "\n";
my $col_separator = ";";

my %row_value_escapes = ( quotemeta($linebreak) => ' ',
                quotemeta($col_separator) => ' ');

GetOptions ("host=s" => \$host,
            "port=i" => \$port,
            "file=s" => \$output_filename,
            "dir=s"  => \$output_dir,
            "user=s" => \$user,
            "pass=s" => \$pass,
            "period=s" => \$period,
            'verbose+' => \$verbose) or fatal("Error in command line arguments");

use constant BALANCEINTERVALS_MODE => 'balanceintervals';
use constant TOPUPLOG_MODE => 'topuplog';

use constant THIS_WEEK_PERIOD => 'this_week';
use constant TODAY_PERIOD => 'today';
use constant THIS_MONTH_PERIOD => 'this_month';
use constant LAST_WEEK_PERIOD => 'last_week';
use constant LAST_MONTH_PERIOD => 'last_month';

my @mode_strings = (BALANCEINTERVALS_MODE,TOPUPLOG_MODE);
my @period_strings = (THIS_WEEK_PERIOD,TODAY_PERIOD,THIS_MONTH_PERIOD,LAST_WEEK_PERIOD,LAST_MONTH_PERIOD);
my $mode = shift @ARGV;

fatal('No mode argument specified, one of [' . join(', ',@mode_strings). "] required") unless $mode;

$output_dir .= '/' if $output_dir && '/' ne substr($output_dir,-1);
$output_filename =  "api_dump_" . $mode . "_results_" . datetime_to_string(current_local()) . ".txt" unless $output_filename;
$output_filename = $output_dir . $output_filename;

my $uri = 'https://'.$host.':'.$port;
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;
$ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
$ua->credentials($netloc, "api_admin_http", $user, $pass);

if (BALANCEINTERVALS_MODE eq $mode) {
    
    my @cols = (
        'subscriber_id',
        'subscriber_status',
        'primary_number',
        'contract_id',
        'contract_status',
        #'has_actual_balance_interval',
        'interval_start',
        'interval_stop',
        'cash_balance',
        'notopup_discard',
    );
    
    my $rowcount = 0;
    my $fh = prepare_file($mode,$output_filename,\@cols);
    
    process_collection($uri.'/api/subscribers',50,'ngcp:subscribers',sub {
        my ($subscriber,$total_count,$customer_map,$package_map,$last_intervals_map,$first_intervals_map,$topup_intervals_map) = @_;
        my $primary_number = get_primary_number($subscriber);
        log_info("processing subscriber ID $subscriber->{id}: " . $primary_number);        
        my ($customer,$last_interval,$package,$first_interval,$topup_interval) = ({},{},{},undef,undef);
        
        $customer = get_item($subscriber->{_links},'ngcp:customers',$customer_map,$subscriber->{customer_id});
        $package = get_item($subscriber->{_links},'ngcp:profilepackages',$package_map,$customer->{profile_package_id});
        
        if (exists $last_intervals_map->{$customer->{id}}) {
            $last_interval = $last_intervals_map->{$customer->{id}};
            $topup_interval = $topup_intervals_map->{$customer->{id}};
            $first_interval = $first_intervals_map->{$customer->{id}};
        } else {
            my $interval = undef;
            my $interval_w_topup = undef;
            my $initial_interval = undef;
            process_collection($uri.'/api/balanceintervals/'.$customer->{id}.'?order_by=end&order_by_direction=desc',
                (defined $package->{notopup_discard_intervals} ? 5 : 1),'ngcp:balanceintervals',sub {
                    my $balance_interval = shift;
                    log_info("processing balance interval: contract ID $subscriber->{customer_id}, " . $balance_interval->{start} . ' - ' . $balance_interval->{stop} );
                    if (defined $package->{notopup_discard_intervals}) {
                        $interval = $balance_interval if !defined $interval;
                        if ($balance_interval->{topup_count} > 0) {
                            $interval_w_topup = $balance_interval;
                            return 0;
                        } else {
                            $initial_interval = $balance_interval;
                        }
                        return 1;
                    } else {
                        $interval = $balance_interval;
                        return 0;
                    }
                });
            $last_interval = $interval if defined $interval;
            $last_intervals_map->{$customer->{id}} = $interval;
            $topup_interval = $interval_w_topup if defined $interval_w_topup;
            $topup_intervals_map->{$customer->{id}} = $topup_interval;
            $first_interval = $initial_interval if !defined $interval_w_topup;
            $first_intervals_map->{$customer->{id}} = $first_interval;
        }    
    
        my %row = (
            'subscriber_id' => $subscriber->{id},
            'subscriber_status' => $subscriber->{status},
            'primary_number' => $primary_number,
            'contract_id' => $customer->{id},
            'contract_status' => $customer->{status},
            #'has_actual_balance_interval' => 1,
            'interval_start' => $last_interval->{start},
            'interval_stop' => $last_interval->{stop},
            'cash_balance' => $last_interval->{cash_balance},
            'notopup_discard' => get_notopup_expiration($package,$last_interval,$topup_interval,$first_interval),
        );

        $rowcount++;
        
        log_row($rowcount,$total_count,\%row,\@cols);
        print $fh join($col_separator,map { escape_row_value($_); } @row{@cols}) . $linebreak;
        
        return 1;
    },5);
    
    close $fh;
    log_info("$rowcount rows written to file '$output_filename'");
} elsif (TOPUPLOG_MODE eq $mode) {
    
    my @cols = (
        'username',
        'timestamp',
        'request_token',
        'subscriber_id',
        'primary_number',
        'contract_id',        
        'outcome',
        'message',
        'type',        
        'voucher_id',
        'voucher_code',
        'amount',
        'cash_balance_before',
        'cash_balance_after',
        'lock_level_before',
        'lock_level_after',
        'package_before',
        'package_after',
        'profile_before',
        'profile_after',
    );
    
    my $rowcount = 0;
    my $fh = prepare_file($mode,$output_filename,\@cols);
    
    my ($from,$to) = get_period_dts();
    my $query_string = (defined $from && defined $to ? '?timestamp_from=' . $from . '&timestamp_to=' . $to : '');
    
    process_collection($uri.'/api/topuplogs'.$query_string,100,'ngcp:topuplogs',sub {
        my ($topuplog,$total_count,$subscriber_map,$voucher_map,$package_map,$profile_map) = @_;
        log_info("processing topup log entry ID $topuplog->{id}");
        
        my ($subscriber,$voucher,$package_before,$package_after,$profile_before,$profile_after) = ({},{},{},{},{},{});
        
        $subscriber = get_item($topuplog->{_links},'ngcp:subscribers',$subscriber_map,$topuplog->{subscriber_id});
        $voucher = get_item($topuplog->{_links},'ngcp:vouchers',$voucher_map,$topuplog->{voucher_id});
        $package_before = get_item($topuplog->{_links},'ngcp:profilepackages',$package_map,$topuplog->{package_before_id});
        $package_after = get_item($topuplog->{_links},'ngcp:profilepackages',$package_map,$topuplog->{package_after_id});
        $profile_before = get_item($topuplog->{_links},'ngcp:billingprofiles',$profile_map,$topuplog->{profile_before_id});
        $profile_after = get_item($topuplog->{_links},'ngcp:billingprofiles',$profile_map,$topuplog->{profile_after_id});

        my %row = (
            'username' => $topuplog->{username},
            'timestamp' => $topuplog->{timestamp},
            'request_token' => $topuplog->{request_token},
            'subscriber_id' => $topuplog->{subscriber_id},
            'primary_number' => get_primary_number($subscriber),
            'contract_id' => $topuplog->{contract_id},
            'outcome' => $topuplog->{outcome},
            'message' => $topuplog->{message},            
            'type' => $topuplog->{type},
            'voucher_id' => $topuplog->{voucher_id},
            'voucher_code' => $voucher->{code},
            'amount' => $topuplog->{amount},
            'cash_balance_after' => $topuplog->{cash_balance_after},
            'cash_balance_before' => $topuplog->{cash_balance_before},
            'lock_level_after' => $topuplog->{lock_level_after},
            'lock_level_before' => $topuplog->{lock_level_before},
            'package_after' => $package_after->{name},
            'package_before' => $package_before->{name},
            'profile_after' => $profile_after->{name},
            'profile_before' => $profile_before->{name},
        );

        $rowcount++;
        
        log_row($rowcount,$total_count,\%row,\@cols);
        print $fh join($col_separator,map { escape_row_value($_); } @row{@cols}) . $linebreak;
        
        return 1;
    },4);
    
    close $fh;
    log_info("$rowcount rows written to file '$output_filename'");
} else {
    fatal("Unknown mode argument '$mode' specified, valid modes are [" . join(', ',@mode_strings). "]") if $mode;
}

exit;

sub process_collection {
    my ($url,$page_size,$item_rel,$process_item,$num_of_helper_maps) = @_;
    my $nexturi = URI->new($url);
    $nexturi->query(($nexturi->query() ? $nexturi->query() . '&' : '') . 'page=1&rows='.$page_size);
    do {
        my $collection = get_request($nexturi);
        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri.$collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }
        my @helper_maps = ();
        for (my $i = 0; $i < $num_of_helper_maps; $i++) {
            push(@helper_maps,{});
        }
        foreach my $item (@{ $collection->{_embedded}->{$item_rel} }) {
            return unless &$process_item($item,$collection->{total_count},@helper_maps);
        }
                     
    } while($nexturi);
}

sub get_item {
    
    my ($_links,$item_rel,$map,$id) = @_;
    
    if (defined $id) {
        if (exists $map->{$id}) {
            return $map->{$id};
        } else {
            #log_info("get profile package ID $customer->{profile_package_id}");
            my $links = $_links->{$item_rel};
            if ('ARRAY' eq ref $links) {
                my %link_map = ();
                foreach my $link (@$links) {
                    next if exists $link_map{$link->{href}};
                    my $item = get_request($uri.$link->{href});
                    $map->{$item->{id}} = $item;
                    $link_map{$link->{href}} = 1;
                }
                return $map->{$id};
            } elsif ('HASH' eq ref $links) {                
                my $item = get_request($uri.$links->{href});
                $map->{$id} = $item;
                return $item;
            }
        }
    }
    
    return {};
}

sub get_request {
    my $url = shift;
    $req = HTTP::Request->new('GET',$url);
    log_debug("GET $url");
    $res = $ua->request($req);
    my $result;
    eval {
        $result = JSON::from_json($res->decoded_content);
    };
    if ($@) {
        fatal("Error requesting api: ".$res->code);
    }
    if ($res->code != 404) {
        fatal("Error requesting api: ".$result->{message}) if $res->code != 200;
    } else {
        $result = {};
    }
    return $result;
}      

sub get_notopup_expiration {
    
    my ($package,$last_interval,$topup_interval,$first_interval) = @_;
    
    my $notopup_expiration = undef;
    
    if ($package && defined $package->{notopup_discard_intervals}) {
        my $start = undef;
        my $notopup_discard_intervals = $package->{notopup_discard_intervals};
        if (is_infinite_future(datetime_from_string($last_interval->{stop}))) {
            $start = datetime_from_string($last_interval->{start});
        } elsif (defined $topup_interval) {
            $start = datetime_from_string($topup_interval->{start});
            $notopup_discard_intervals += 1;
        } elsif (defined $first_interval) {
            $start = datetime_from_string($first_interval->{start});
            $notopup_discard_intervals += 1;
        }
        if (defined $start) {
            $notopup_expiration = add_interval($start,
                $package->{balance_interval_unit},
                $notopup_discard_intervals);
            $notopup_expiration = datetime_to_string($notopup_expiration);
        }
    }
    
    return $notopup_expiration;
}

sub get_timely_start_end {
    
    my ($package,$interval) = @_;
    
    my ($timely_start,$timely_end) = (undef,undef);
    
    if ($package && defined $package->{timely_duration_value}) {
        my $start = datetime_from_string($interval->{start});
        $timely_end = add_interval($start,
                $package->{balance_interval_unit},
                $package->{balance_interval_value});

        $timely_start = add_interval($timely_end,
                $package->{timely_duration_unit},
                -1 * $package->{timely_duration_value},);
        $timely_end = datetime_to_string($timely_end);
        $timely_start = datetime_to_string($timely_start);
    }
    
    return ($timely_start,$timely_end);
}

sub get_primary_number {
    my $subscriber = shift;
    return ($subscriber->{primary_number} ? $subscriber->{primary_number}->{cc} . ' ' . $subscriber->{primary_number}->{ac} . ' ' . $subscriber->{primary_number}->{sn} : $subscriber->{username} . ($subscriber->{domain} ? '@' . $subscriber->{domain} : ''));
}

sub get_period_dts {
    my ($now,$from,$to) = (current_local(),undef,undef);
    my $label;
    if (THIS_WEEK_PERIOD eq $period) {
        $from = $now->truncate(to => 'week');
        $to = $from->clone->add('weeks' => 1)->subtract(seconds => 1);
        $label = 'this week';
    } elsif (TODAY_PERIOD eq $period) {
        $from = $now->truncate(to => 'day');
        $to = $from->clone->add('days' => 1)->subtract(seconds => 1);
        $label = 'today';
    } elsif (THIS_MONTH_PERIOD eq $period) {
        $from = $now->truncate(to => 'month');
        $to = $from->clone->add('months' => 1)->subtract(seconds => 1);
        $label = 'this month';
    } elsif (LAST_WEEK_PERIOD eq $period) {
        $from = $now->truncate(to => 'week')->subtract(seconds => 1)->truncate(to => 'week');
        $to = $from->clone->add('weeks' => 1)->subtract(seconds => 1);
        $label = 'last week';
    } elsif (LAST_MONTH_PERIOD eq $period) {
        $from = $now->truncate(to => 'month')->subtract(seconds => 1)->truncate(to => 'month');
        $to = $from->clone->add('months' => 1)->subtract(seconds => 1);
        $label = 'last week';          
    } else {
        fatal("Unknown period '$period' specified, valid periods are [" . join(', ',@period_strings). "]") if $period;
        return ($from,$to);
    }
    log_info($label .': ' . datetime_to_string($from) . ' to ' . datetime_to_string($to));
    return ($from,$to);
}

sub add_interval {
    my ($from,$interval_unit,$interval_value,$align_eom_dt) = @_;
    if ('day' eq $interval_unit) {
        return $from->clone->add(days => $interval_value);
    } elsif ('hour' eq $interval_unit) {
        return $from->clone->add(hours => $interval_value);        
    } elsif ('week' eq $interval_unit) {
        return $from->clone->add(weeks => $interval_value);
    } elsif ('month' eq $interval_unit) {
        my $to = $from->clone->add(months => $interval_value, end_of_month => 'preserve');
        #DateTime's "preserve" mode would get from 30.Jan to 30.Mar, when adding 2 months
        #When adding 1 month two times, we get 28.Mar or 29.Mar, so we adjust:
        if (defined $align_eom_dt
            && $to->day > $align_eom_dt->day
            && $from->day == last_day_of_month($from)) {
            my $delta = last_day_of_month($align_eom_dt) - $align_eom_dt->day;
            $to->set(day => last_day_of_month($to) - $delta);
        }
        return $to;
    }
    return undef;
}

sub datetime_from_string {
    my $s = shift;
    $s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
    my $ts = DateTime::Format::ISO8601->parse_datetime($s);
    $ts->set_time_zone( DateTime::TimeZone->new(name => 'local') );
    return $ts;
}

sub datetime_to_string {
    my $dt = shift;
    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );
    return $dtf->format_datetime($dt);
}

sub last_day_of_month {
    my $dt = shift;
    return DateTime->last_day_of_month(year => $dt->year, month => $dt->month,
                                       time_zone => DateTime::TimeZone->new(name => 'local'))->day;
}

sub is_infinite_future {
	my $dt = shift;
	return $dt->year >= 9999;
}

sub current_local {
    return DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
}

sub prepare_file {
    my ($mode,$output_filename,$cols) = @_;
    log_info("dumping $mode into file $output_filename ...");
    my $fh;
    open($fh, '>', $output_filename) or fatal("Could not open file '$output_filename' $!");
    
    if ($print_colnames) {
        print $fh join($col_separator,@$cols) . $linebreak;
    }
    return $fh;
}

sub escape_row_value {
    my $value = shift;
    foreach my $escape (keys %row_value_escapes) {
        $value =~ s/$escape/$row_value_escapes{$escape}/g;
    }
    return $value;
}

sub log_row {
    my ($rowcount,$total_count,$row,$cols) = @_;
    my $label = "writing row $rowcount of $total_count ";
    my $rep = 56;
    log_debug($label . '=' x ($rep - length($label)) . "\n" . join("\n",map { '  ' . $_ . ' = ' . $row->{$_}; } @$cols) . "\n" . '=' x $rep);
}

sub log_info {
    my $msg = shift;
    print $msg . "\n" if $verbose > 0;    
}

sub log_debug {
    my $msg = shift;
    print $msg . "\n" if $verbose > 1;
}

sub fatal {
    my $msg = shift;
    die($msg . "\n");
}