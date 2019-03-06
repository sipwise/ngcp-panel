package NGCP::Panel::Utils::TimeSet;

use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime;
use Data::ICal;

use constant CALENDAR_MIME_TYPE => 'text/calendar';

sub get_calendar_file_name {
    my %params = @_;
    my($c, $timeset) = @params{qw/c timeset/};
    my $name = $timeset->name;
    #replacement not collapsed intentionally
    $name =~s/[^[:alnum:] ]/_/g;
    return $name.'_'.$timeset->id;
}

sub delete_timeset {
    my %params = @_;
    my($c, $timeset) = @params{qw/c timeset/};

    $timeset->delete();
}

sub update_timeset {
    my %params = @_;
    my($c, $timeset, $resource) = @params{qw/c timeset resource/};

    $timeset->update({
            name => $resource->{name},
            reseller_id => $resource->{reseller_id},
        })->discard_changes;

    $timeset->time_periods->delete;
    create_timeset_events(
        c       => $c,
        timeset => $timeset,
        events  => $resource->{times},
    );
}

sub create_timeset {
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

sub timeset_resource {
    my (%params) = @_;

    my $c = $params{c};
    my $api_format = $params{api_format};
    my $resource = $params{resource}
        // ( $params{form} ? $params{form}->values : {});

    delete $resource->{calendarfile};
    if($c->user->roles eq 'admin') {
        if ($resource->{reseller}) {
            if ( !$resource->{reseller_id} ) {
                $resource->{reseller_id} = $resource->{reseller}{id};
            }
            delete $resource->{reseller};
        }
    }  elsif($c->user->roles eq 'reseller') {
        $resource->{reseller_id} = $c->user->reseller_id;
    }
    if (!$resource->{name}) {
        my( $calendar_parsed ) = NGCP::Panel::Utils::TimeSet::parse_calendar(
            c => $c,
        );
        #we have checked that $name is not empty in the form validation
        $resource->{name} = $calendar_parsed->{name};
    }
    #data taken from the request parameters or cache has higher priority
    my($events, $fails, $text_success);
    #empty array from json input will be not overwritten, only if json "times" was not set 
    if (!$resource->{times}) {
        ($events, $fails, $text_success) = NGCP::Panel::Utils::TimeSet::parse_calendar_events(c => $c);
        $resource->{times} = $events;
    }
    return $resource;
}


sub get_calendar_data_parsed {
    my %params = @_;
    my($c, $data) = @params{qw/c data/};
    use Carp qw/longmess/;
    $c->log->debug(longmess);
    if ($c->stash->{calendar_upload_parsed}) {
        return $c->stash->{calendar_upload_parsed};
    }
    if (!$data && $c->req->upload('calendarfile')) {
        $data = \$c->req->upload('calendarfile')->slurp;
        $data //= '';
        $$data =~s/\n+/\n/g;
        $c->stash(
            calendar_upload => $data,
        );
    }
    if (!$data) {
        return;
    }
    $c->log->debug("calendar data: ".$$data.";");
    my $calendar = Data::ICal->new( data => $$data );
    if (!$calendar) {
        #https://metacpan.org/pod/Data::ICal
        #parse [ data => $data, ] [ filename => $file, ]
        #Returns $self on success. Returns a false value upon failure to open or parse the file or data; this false value is a Class::ReturnValue object and can be queried as to its error_message.
        $c->log->debug("calendar error messages: ".$calendar->error_message.";");
    } else {
        $c->stash(
            calendar_upload_parsed => $calendar,
        );
    }
    return $calendar, $data;
}

sub parse_calendar{
    my %params = @_;
    my($c, $data) = @params{qw/c data/};

    my $timeset = {};

    #we will use caching because we need to parse uploaded fie to check name existence and uniqueness
    if ($c->stash->{calendar_upload_parsed_result}) {
        return $c->stash->{calendar_upload_parsed_result}, $c->stash->{calendar_upload_parsed};
    }
    my ($calendar) = get_calendar_data_parsed( c=> $c, data => $data );
    if ($calendar) {
        if ($calendar->property('name')) {
            $timeset->{name} = $calendar->property('name')->[0]->value;
        }
    }
    $c->stash(
        calendar_upload_parsed => $calendar,
        calendar_upload_parsed_result => $timeset,
    );
    return $timeset, $calendar;
}

sub parse_calendar_events {
    my %params = @_;
    my($c, $calendar, $data, $api_format) = @params{qw/c calendar data api_format/};
    my ($events, $fails, $text_success) = ([], undef, 'Calendar events successfully uploaded');
    if(!$calendar) {
        if (!$c->stash->{calendar_upload_parsed}) {
            ($calendar) = get_calendar_data_parsed( c=> $c, data => $data );
        }
    }
    if ($calendar) {
        $c->log->debug("parse calendar events;");
        my @allowed_rrule_fields = (qw/FREQ COUNT UNTIL INTERVAL BYSECOND BYMINUTE BYHOUR BYDAY BYMONTHDAY BYYEARDAY BYWEEKNO BYMONTH BYSETPOS WKST SUMMARY/);
        my @all_rrule_fields = (@allowed_rrule_fields, qw/RDATE EXDATE/);
        my %rrule_fields_end_markers = map { 
            my $field = $_; 
            $field => join('|', grep {$_ ne $field} @all_rrule_fields)
        } @all_rrule_fields;
        #or:
        #my $rrule_fields_end_marker = '[a-z]+';
        my @datetime_fields = qw/dtstart dtend until/;
        my $mapped_fields = {
            'dtstart' => 'start',
            'dtend' => 'end',
            'summary' => 'comment',
        };
        foreach my $entry (@{$calendar->entries}) {
            $c->log->debug("parse calendar entry:".$entry->as_string .";");
            my $event = {
                map {
                    $entry->property($_) 
                        ? ( $_ => $entry->property($_)->[0]->value )
                        : ()
                } qw/summary dtstart dtend/
            };
            my $rrule = $entry->property('rrule');
            if ( ref $rrule eq 'ARRAY' && @$rrule ) {
                #we don't expect some RRULE spec in one event for now
                my $rrule_data = { map {
                    my $FIELD = $_;
                    my $field = lc($FIELD);
                    my $re = '(?:^|;)'.$FIELD.'=(.*?)(?:;(?:'.$rrule_fields_end_markers{$FIELD}.')|;$|$)';
                    $rrule->[0]->value =~/$re/i;
                    my $value = $1;
                    if ($value) {
                        ($field => $value);
                    } else {
                        ();
                    }
                } @allowed_rrule_fields };
                $event = {%$event, %$rrule_data};
            }
            foreach my $dt_field (@datetime_fields) {
                if ($event->{$dt_field}) {
                    $event->{$dt_field} =~s/^\s*(\d{4})\D*(\d{2})\D*(\d{2})(\D*)(\d{2})\D*(\d{2})\D*(\d{2}).*?\s*$/$1-$2-$3$4$5:$6:$7/;
                }
            }
            foreach my $ical_field (keys %$mapped_fields) {
                if ($event->{$ical_field}) {
                    $event->{$mapped_fields->{$ical_field}} = delete $event->{$ical_field};
                }
            }
            push @$events, $event;
        }
    }
    return $events, $fails, $text_success;
}
1;

=head1 NAME

NGCP::Panel::Utils::TimeSet

=head1 DESCRIPTION

A temporary helper to manipulate resellers data

=head1 METHODS

=head2 update_timeset

Update timesets database data

=head2 create_timeset

Create timeset database data

=head2 get_timeset

Get timesets data from database to show to the user

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
