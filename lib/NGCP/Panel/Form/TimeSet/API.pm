package NGCP::Panel::Form::TimeSet::API;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'reseller_id' => (
    type => 'Integer',
    required => 1,
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
        title => ['An array of time definitions with a number of optional and mandatory keys.']
    },
);

has_field 'times.id' => (
    type => 'Hidden',
);

has_field 'times.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'Start',
    required => 1,
);

has_field 'times.end' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'End',
);

has_field 'times.freq' => (
    type => 'Select',
    label => 'Frequency',
    options => [
        map { +{value => $_, label => $_}; } (qw/secondly minutely hourly daily weekly monthly yearly/)
    ],
);

has_field 'times.until' => (
    label => 'Until',
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['Can\'t be defined together with "Count".']
    },
);

has_field 'times.count' => (
    type => 'PosInteger',
    label => 'Count',
    element_attr => {
        rel => ['tooltip'],
        title => ['Valid value is a positive integer. Can\'t be defined together with "Until".']
    },
);

has_field 'times.interval' => (
    type => 'PosInteger',
    label => 'Interval',
    element_attr => {
        rel => ['tooltip'],
        title => ['Valid value is a positive integer.']
    },
);

has_field 'times.bysecond' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By second',
    min_value => 0,
    max_value => 59,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 59, i.e. 1,3,59.']
    },
);

has_field 'times.byminute' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By minute',
    min_value => 0,
    max_value => 59,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 59, i.e. 1,3,59.']
    },
);

has_field 'times.byhour' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By hour',
    min_value => 0,
    max_value => 23,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 0 to 23, i.e. 1,3,23.']
    },
);

has_field 'times.byday' => (
    type => 'Text', # (\+|-)?\d*(MO|DI|MI|DO|FR|SA|SU)
    label => 'By day',
    element_attr => {
        rel => ['tooltip'],
        title => ['Value format is ~[+|-~]~[NUMBER~](MO|DI|MI|DO|FR|SA|SU). Example: 5FR (means fifth friday).']
    },
    # example: 5FR (means fifth friday)
);

has_field 'times.bymonthday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By month day',
    min_value => 1,
    max_value => 31,
    plusminus => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 31, i.e. 1,3,31.']
    },
);

has_field 'times.byyearday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By year day',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 366, i.e. 1,3,366.']
    },
);

has_field 'times.byweekno' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By week number',
    min_value => 1,
    max_value => 53,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 53, i.e. 1,3,53.']
    },
);

has_field 'times.bymonth' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By month',
    min_value => 1,
    max_value => 12,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 12, i.e. 1,3,12.']
    },
);

has_field 'times.bysetpos' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By set position',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Value is set of numbers from 1 to 366, i.e. 1,3,366.']
    },
);

has_field 'times.comment' => (
    type => 'Text',
    label => 'Comment',
);



1;

# vim: set tabstop=4 expandtab:
