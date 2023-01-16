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
            return;
        }
    } elsif ($subscriber and $c->req->param('use_owner_tz')) {
        my $tz = $c->model('DB')->resultset('voip_subscriber_timezone')->search_rs({
            subscriber_id => $subscriber->id
        })->first;
        $tz_name = NGCP::Panel::Utils::DateTime::normalize_db_tz_name($tz->name) if $tz;
    }
    $times //= [];
    my $tz_local = DateTime::TimeZone->new(name => 'local');
    my ($tz,$offset);
    if ($tz_name
        and ($tz = DateTime::TimeZone->new(name => $tz_name))
        and abs($offset = $tz->offset_for_datetime(DateTime->now()) - $tz_local->offset_for_datetime(DateTime->now())) > 0) {

        my $offset_hrs = int($offset / 3600.0);
        if ($offset_hrs * 3600 != $offset) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "only full hours supported for timezone offset ($tz_name: $offset seconds = $offset_hrs hours)");
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
            $c->log->debug("cf timeset $mode for timezone $tz_name: offset $offset_hrs hours");
        } elsif ('inflate' eq $mode) { #for reading from db
            $merge = 1;
            $c->log->debug("cf timeset $mode for timezone $tz_name: offset $offset_hrs hours");
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
                push(@$times,@{_add($yearmonthmday_map->{$yearmonthmday},$offset_hrs,$merge)});
            } else {
                push(@$times,@{_subtract($yearmonthmday_map->{$yearmonthmday},$offset_hrs,$merge)});
            }
        }

    } else {
        $c->log->debug("no timezone to convert to, or zero tz offset");
    }
    return $times;

}

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
    # enable tz and use_owner_tz params for GET:
    #$resource{times} = $self->apply_owner_timezone($c,$item->subscriber->voip_subscriber,\@times,'inflate');

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

    $self->expand_fields($c, \%resource);
    $hal->resource(\%resource);
    return $hal;
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if ($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets');
    } elsif ($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        my $reseller_id = $c->user->reseller_id;
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets')->search_rs({
            'reseller_id' => $reseller_id,
        },{
            join => {'subscriber' => {'contract' => 'contact'} },
        });
    } elsif ($c->user->roles eq "subscriberadmin") {
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets')->search_rs({
            'subscriber.account_id' => $c->user->account_id,
        },{
            join => 'subscriber',
        });
    } elsif ($c->user->roles eq "subscriber") {
        $item_rs = $c->model('DB')->resultset('voip_cf_time_sets')->search_rs({
            '-or' => [
                'me.subscriber_id' => $c->user->id,
                'voip_cf_mappings.subscriber_id' => $c->user->id,
            ]
        },{
            distinct => 1,
            join => 'voip_cf_mappings',
        });
    }

    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub check_subscriber_can_update_item {
    my ($self, $c, $item) = @_;

    if ($c->user->roles eq 'subscriber' && $c->user->id != $item->subscriber_id) {
        $self->error($c, HTTP_FORBIDDEN, "This time set does not belong to the user");
        return;
    }

    return 1;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');

    return unless $self->check_subscriber_can_update_item($c, $item);

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

    my $times = $resource->{times};
    # enable tz and use_owner_tz params for PUT/PATCH/POST:
    #$times = $self->apply_owner_timezone($c,$b_subscriber,$resource->{times},'deflate');

    try {
        $item->update({
                name => $resource->{name},
                subscriber_id => $subscriber->id,
            })->discard_changes;
        $item->voip_cf_periods->delete;
        for my $t ( @$times ) {
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
