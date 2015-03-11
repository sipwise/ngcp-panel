package NGCP::Panel::Field::E164RangeRepeat;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Repeatable';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'e164range' => (
    type => '+NGCP::Panel::Field::E164Range', 
    order => 99,
    required => 0,
    label => 'Number Range',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);


1;

# vim: set tabstop=4 expandtab:
