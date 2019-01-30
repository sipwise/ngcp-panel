package NGCP::Panel::Utils::TimeSet;

use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime;
use Data::ICal;
use iCal::Parser;

sub delete_timesets {
    my %params = @_;
    my($c, $timeset) = @params{qw/c timeset/};

    $timeset->delete();
}

sub update_timesets {
    my %params = @_;
    my($c, $timeset, $resource) = @params{qw/c timeset resource/};

    $timeset->update({
            name => $resource->{name},
            reseller_id => $resource->{reseller_id},
        })->discard_changes;
    $timeset->time_periods->delete;
    for my $t ( @{$resource->{times} } ) { 
        $timeset->create_related("time_periods", {
            %{ $t },
        });
    }
}

sub create_timesets {
    my %params = @_;
    my($c, $resource) = @params{qw/c resource/};

    my $schema = $c->model('DB');
    my $timeset = $schema->resultset('voip_time_sets')->create({
        name => $resource->{name},
        reseller_id => $resource->{reseller_id},
    });
    create_timeset_events(
        c       => $c,
        timeset => $timeset,
        events  => $resource->{times},
    );
    for my $t ( @{$resource->{times}} ) {
        $timeset->create_related("time_periods", {
            %{ $t },
        });
    }
    return $timeset;
}

sub create_timeset_events {
    my %params = @_;
    my($c, $timeset, $events) = @params{qw/c timeset events/};
    $events //= [];
    for my $t ( @{$events} ) {
        $timeset->create_related("time_periods", {
            %{ $t },
        });
    }
    return $timeset;
}

sub get_timeset {
    my %params = @_;
    my($c, $timeset, $date_mysql_format) = @params{qw/c timeset date_mysql_format/};

    my $resource = { $timeset->get_inflated_columns };

    my @periods;
    for my $period ($timeset->time_periods->all) {
        my $period_infl = { $period->get_inflated_columns, };
        delete @{ $period_infl }{'time_set_id', 'id'};
        if (!$date_mysql_format) {
            foreach my $date_key (qw/start end until/) {
                if (defined $period_infl->{$date_key}) {
                    $period_infl->{$date_key} = NGCP::Panel::Utils::DateTime::from_mysql_to_js($period_infl->{$date_key});
                }
            }
        }
        for my $k (keys %{ $period_infl }) {
            delete $period_infl->{$k} unless defined $period_infl->{$k};
        }
        push @periods, $period_infl;
    }
    $resource->{times} = \@periods;
    return $resource;
}

sub get_timeset_icalendar {
    my %params = @_;
    my($c, $timeset) = @params{qw/c timeset/};
    my $data = '';
    my $data_ref = $timeset->timeset_ical ? \$timeset->timeset_ical->ical : \$data;
    return $data_ref;
}

sub parse_calendar{
    my %params = @_;
    my($c, $timeset_in, $data) = @params{qw/c timeset data/};

    $timeset_in //= {};
    my $timeset = {%$timeset_in};

    #we will use caching because we need to parse uploaded fie to check name existence and uniqueness
    if ($c->stash->{parsed_calendar}) {
        return $c->stash->{parsed_calendar}, $c->stash->{parsed_calendar_result};
    }

    if (!$data) {
        my $upload = $c->req->upload('upload')->slurp;
        $data = \$upload->slurp;
        
    }
    if (!$data && !ref $data && !$$data) {
        return $timeset;
    }
    $$data =~s/\n+/\n/g;
    $c->log->debug("calendar data: ".$$data.";");

    my $calendar = Data::ICal->new( data => $$data );
    if (!$calendar) {
        #https://metacpan.org/pod/Data::ICal
        #parse [ data => $data, ] [ filename => $file, ]
        #Returns $self on success. Returns a false value upon failure to open or parse the file or data; this false value is a Class::ReturnValue object and can be queried as to its error_message.
        $c->log->debug("calendar error messages: ".$calendar->error_message.";");
        return $timeset;
    } else {
        if ($calendar->property('name')) {
            $timeset->{name} = $calendar->property('name')->[0]->value;
        }
    }
    $c->stash(
        parsed_calendar => $calendar,
        parsed_calendar_result => $timeset,
    );
    return $timeset, $calendar;
}

sub parse_calendar_events {
    my %params = @_;
    my($c, $calendar) = @params{qw/c calendar/};
    $calendar //= $c->stash->{parsed_calendar};

    my $events = [];

    if ($calendar) {
        my @allowed_rrule_fields = (qw/FREQ COUNT UNTIL INTERVAL BYSECOND BYMINUTE BYHOUR BYDAY BYMONTHDAY BYYEARDAY BYWEEKNO BYMONTH BYSETPOS WKST RDATE EXDATE/);
        my %rrule_fields_end_markers = map { 
            my $field = $_; 
            $field => join('|', grep {$_ ne $field} @allowed_rrule_fields)
        } @allowed_rrule_fields;
        #or:
        #my $rrule_fields_end_marker = '[a-z]+';
        foreach my $entry (@{$calendar->entries}) {
            my $event = {
                comment => $calendar->property('description')->[0]->value,
            };
            my $rrule = $entry->property('rrule');
            if ( ref $rrule eq 'ARRAY' && @$rrule ) {
                #we don't expect some RRULE spec in one event for now
                my $rrule_data = { map {
                    my $re = '(?:^|;)'.$_.'=(.*?)(?:;(?:'.$rrule_fields_end_markers{$_}.')|;$|$)';
                    $rrule->[0]->value =~/$re/i;
                    $1 ? ($_ => $1) : ();
                } @allowed_rrule_fields };
                $event = {%$event, %$rrule_data};
            }
            push @$events, $event;
        }
    }
    return $events;
}
1;

=head1 NAME

NGCP::Panel::Utils::TimeSet

=head1 DESCRIPTION

A temporary helper to manipulate resellers data

=head1 METHODS

=head2 update_timesets

Update timesets database data

=head2 create_timesets

Create timesets database data

=head2 get_timesets

Get timesets data from database to show to the user

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
