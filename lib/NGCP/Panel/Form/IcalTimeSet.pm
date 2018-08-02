package NGCP::Panel::Form::IcalTimeSet;
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
    required => 1,
);
has_field 'times.end' => (
    type => '+NGCP::Panel::Field::DateTime',
);
has_field 'times.freq' => (
    type => 'Select',
    options => [
        map { +{value => $_, label => $_}; } (qw/secondly minutely hourly daily weekly monthly yearly/)
    ],
);
has_field 'times.until' => (
    type => '+NGCP::Panel::Field::DateTime',
);
has_field 'times.count' => (
    type => 'PosInteger',
);
has_field 'times.interval' => (
    type => 'PosInteger',
);
has_field 'times.bysecond' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 0,
    max_value => 60,
);
has_field 'times.byminute' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 0,
    max_value => 59,
);
has_field 'times.byhour' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 0,
    max_value => 60,
);
has_field 'times.byday' => (
    type => 'Text', # (\+|-)?\d*(MO|DI|MI|DO|FR|SA|SU)
    # example: 5FR (means fifth friday)
);
has_field 'times.bymonthday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 1,
    max_value => 31,
    plusminus => 1,
);
has_field 'times.byyearday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
);
has_field 'times.byweekno' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 1,
    max_value => 53,
);
has_field 'times.bymonth' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 1,
    max_value => 12,
);
has_field 'times.bysetpos' => (
    type => '+NGCP::Panel::Field::IntegerList',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
);
has_field 'times.comment' => (
    type => 'Text',
);



1;

# vim: set tabstop=4 expandtab:
