package NGCP::Panel::Role::API::CFTimeSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Utils::Subscriber;

use NGCP::Panel::Form;

use NGCP::Panel::Utils::DateTime qw();

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFTimeSetSubAPI", $c);
    } else {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CallForward::CFTimeSetAPI", $c);
    }
}

sub apply_owner_timezone {

    my ($self, $c, $subscriber, $times, $mode) = @_;

    my $tz_name;
    if($c->req->param('tz')) {
        if (DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $tz_name = $c->req->param('tz');
        } else {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return undef;
        }
    } elsif ($subscriber and $c->req->param('use_owner_tz')) {
        my $tz = $c->model('DB')->resultset('voip_subscriber_timezone')->search_rs({
            subscriber_id => $subscriber->id
        })->first;
        $tz_name = NGCP::Panel::Utils::DateTime::normalize_db_tz_name($tz->name) if $tz;
    }
    $times //= [];
    if ($tz_name
        and (my $tz = DateTime::TimeZone->new(name => $tz_name))
        and (my $offset = $tz->offset_for_datetime(NGCP::Panel::Utils::DateTime::current_local())) > 0) {

        my $offset_hrs = int($offset / 3600.0);
        if ($offset_hrs * 3600 != $offset) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "only full hours supported for timezone offset ($tz_name: $offset seconds = $offset_hrs hours)");
            return undef;
        }

        foreach my $time (@$times) {
            foreach $field (qw(year month mday) {
                if (exists $time->{$field} and $time->{$field}) {
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "cannot apply a timezone offset for time with '$field' field ($time->{$field})");
                    return undef;
                }
            }
        }

        if ('deflate' eq $mode) {
            $c->log->debug("cf timeset $mode for timezone $tz_name: offset $offset_hrs hours");
        } elsif ('inflate' eq $mode) {
            $offset_hrs = $offset_hrs * -1;
            $c->log->debug("cf timeset $mode for timezone $tz_name: offset $offset_hrs hours");
        } else {
            die("invalid mode $mode");
        }

        return $self->_times_convert_tz();

    }
    return $times;

}

sub expand {
    my ($times,$offset_hrs);

    my @result = ();
    foreach my $time (@$times) {
        my $p1 = { %$time };
        unless (length($time->{hour}) > 0) {
            #nothing to do if there is no hour defined:
            push(@result,$p1);
            next;
        }
        my ($hour_start,$hour_end) = split(/\-/, $time->{hour};
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

sub expand {
    my ($times,$offset_hrs);

    my @result = ();
    foreach my $time (@$times) {
        my $p1 = { %$time };
        unless (length($time->{hour}) > 0) {
            #nothing to do if there is no hour defined:
            push(@result,$p1);
            next;
        }
        my ($hour_start,$hour_end) = split(/\-/, $time->{hour};
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

sub x {

    my @wdays = ();
    my $idx = 0;
    foreach my $time (@$times) {
        $idx++;
        next unless length($time->{hour}) > 0;
        my ($start, $end) = split(/\-/, $time->{wday} || '1-7');
        $end //= $start;
        my @nums = ();
        if ($start <= $end) {
            push(@nums,$start .. $end);
        } else {
            push(@nums,$start .. 7);
            push(@nums,1 .. $end);
        }
        foreach my $val ($start .. $end) {
            my %t = %$times;
            $t{wday} = $val;
            $t{idx} = $idx;
            ($t{hour_start},$t{hour_end}) = split(/\-/, $time->{hour};
            $t{hour_end} //= $t{hour_start};
            push(@wdays,\%t) if $t{hour_end} < $t{hour_start};
        }
    }

    my @adjacent_wday_groups = ();
    $idx = 0;
    foreach my $time (sort {
            $a->{wday} <=> $b->{wday} || $a->{hour_start} <=> $b->{hour_start} || $a->{idx} <=> $b->{idx}
        } @wday_deflated) {
        if ($idx > 0 and $wday_deflated[$idx - 1]) {

        }
        $idx++;
    }

    my @adjacent_wday_groups = ();
    foreach my $time (@$times) {
        $wday_groups{$time->{wday}} =
    }

    my %grouped = ();
    foreach my $field (qw(wday hour)) {
        $grouped{join(',',sort keys %grouped,$field)} =
    }

    foreach my $time (@$times) {
        foreach $field (qw(wday hour minute) {
            $grouped{$field} =

    "year", "month", "mday", "wday", "hour", "minute"

    my ($start, $end) = split(/\-/, $time->{$field});
    $end //= $start;

    sub powerset {
        return [[]] if @_ == 0;
        my $first = shift;
        my $pow = &powerset;
        [ map { [$first, @$_ ], [ @$_] } @$pow ];
    }
}

sub hal_from_item {
    my ($self, $c, $item, $type) = @_;
    my $form;

    my %resource = $item->get_inflated_columns;
    my @times;
    for my $time ($item->voip_cf_periods->all) {
        my $timeelem = {$time->get_inflated_columns};
        delete $timeelem->{'id'};
        push @times, $timeelem;
    }
    $resource{times} = \@times;

    my $b_subs_id = $item->subscriber->voip_subscriber->id;
    $resource{subscriber_id} = $b_subs_id;

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("%s", $self->dispatch_path)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:$type", href => sprintf("/api/%s/%d", $type, $item->id)),
            Data::HAL::Link->new(relation => "ngcp:subscribers", href => sprintf("/api/subscribers/%d", $b_subs_id)),
            $self->get_journal_relation_link($c, $item->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets');
    } elsif ($c->user->roles eq "reseller") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets')
            ->search_rs({
                    'reseller_id' => $reseller_id,
                } , {
                    join => {'subscriber' => {'contract' => 'contact'} },
                });
    } elsif($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets')
            ->search_rs({
                    'subscriber_id' => $c->user->id,
                });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    if (! exists $resource->{times} ) {
        $resource->{times} = [];
    }
    if (ref $resource->{times} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'times'. Must be an array.");
        return;
    }

    if($c->user->roles eq "subscriber" || $c->user->roles eq "subscriberadmin") {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    }

    my $b_subscriber = $schema->resultset('voip_subscribers')->find($resource->{subscriber_id});
    unless ($b_subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
        return;
    }
    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        last;
    }

    try {
        $item->update({
                name => $resource->{name},
                subscriber_id => $subscriber->id,
            })->discard_changes;
        $item->voip_cf_periods->delete;
        for my $t ( @{$resource->{times}} ) {
            delete $t->{time_set_id};
            $item->create_related("voip_cf_periods", $t);
        }
    } catch($e) {
        $c->log->error("failed to create cftimeset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cftimeset.");
        return;
    };

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
