#!/usr/bin/env perl

# need cpan libaries:
# cpanm Data::ICal Data::ICal::DateTime DateTime::Set

use warnings;
use strict;

use DateTime;
use DateTime::Set;
use DateTime::Duration;
use Data::ICal;
use Data::ICal::DateTime;

use DDP use_prototypes=>0;

my $calendar;
# $calendar = Data::ICal->new(filename => 'sandbox/weekdays_ninetofive.ics'); # parse existing file
$calendar = Data::ICal->new(filename => 'sandbox/repeat_with_gaps_edits.ics'); # parse existing file

# p $calendar;
# p $calendar->entries->[1];
# p $calendar->events;
my ($event) = $calendar->events;

# p $event;

# p $event->start;
# p $event->duration;
# p $event->summary;
# p $event->start->ymd.":".$event->start->hms;
# p $event->end->ymd.":".$event->end->hms;

# hack to get duration of single recurrence:
my $duration = 
	DateTime::Span->from_datetimes(
		start => $event->start,
		end => $event->end)
	->duration;

p $duration;

my $set = $event->recurrence;

# p $set->span;
# p $set->span->duration;
# p $set->next->end;

p "looping";

# p $set;
# p $set->as_list;
for my $i (1..15) {
	my $n = $set->next;
	my $start_string = $n->ymd." ".$n->hms;

	my $end = $n->add($duration);
	my $end_string = $end->ymd." ".$end->hms;	

	p $start_string." -- ".$end_string;
}
# p $set->as_list;

exit 0;