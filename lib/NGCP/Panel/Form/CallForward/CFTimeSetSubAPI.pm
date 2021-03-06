package NGCP::Panel::Form::CallForward::CFTimeSetSubAPI;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
);

has_field 'times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of time definitions with keys "year", "month", "mday", "wday", "hour", "minute", where each value can be a number like "10" or a range like "10-20".']
    },
);

has_field 'times.id' => (
    type => 'Hidden',
);

has_field 'times.year' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 1990,
    max_end => 3000,
    label => 'Year',
    empty_select => '',
);
has_field 'times.month' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 1,
    max_end => 12,
    cyclic => 1,
    label => 'Month',
    empty_select => '',
);
has_field 'times.mday' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 1,
    max_end => 31,
    cyclic => 1,
    label => 'Day',
);

has_field 'times.wday' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 1,
    max_end => 7,
    cyclic => 1,
    label => 'Weekday',
    empty_select => '',
);

has_field 'times.hour' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 0,
    max_end => 23,
    cyclic => 1,
    label => 'Hour',
    empty_select => '',
);

has_field 'times.minute' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 0,
    max_end => 59,
    cyclic => 1,
    label => 'Minute',
    empty_select => '',
);

1;

# vim: set tabstop=4 expandtab:
