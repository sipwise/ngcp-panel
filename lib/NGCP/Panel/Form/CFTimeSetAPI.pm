package NGCP::Panel::Form::CFTimeSetAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
);

has_field 'subscriber' => ( # Workaround for validate_form
    type => 'Compound',
);

has_field 'subscriber.id' => (
    type => 'PosInteger',
);

has_field 'times' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
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
    label => 'Month',
    empty_select => '',
);
has_field 'times.mday' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 1,
    max_end => 31,
    label => 'Day',
);

has_field 'times.wday' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 1,
    max_end => 8,
    label => 'Weekday',
    empty_select => '',
);

has_field 'times.hour' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 0,
    max_end => 23,
    label => 'Hour',
    empty_select => '',
);

has_field 'times.minute' => (
    type => '+NGCP::Panel::Field::NumRangeAPI',
    min_start => 0,
    max_end => 59,
    label => 'Minute',
    empty_select => '',
);

1;

# vim: set tabstop=4 expandtab:
