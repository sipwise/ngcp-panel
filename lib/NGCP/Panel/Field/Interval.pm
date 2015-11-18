package NGCP::Panel::Field::Interval;
use Moose;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'value' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The duration/interval in temporal units.']
    },
    do_label => 0,
    do_wrapper => 0,  
);

has_field 'unit' => (
    type => 'Select',
    options => [
        { value => 'hour', label => 'hour(s)' },
        { value => 'day', label => 'day(s)' },
        { value => 'week', label => 'week(s)' },
        { value => 'month', label => 'month(s)' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The temporal unit for the duration/interval.']
    },
    do_label => 0,
    do_wrapper => 0,  
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
