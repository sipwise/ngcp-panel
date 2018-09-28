package NGCP::Panel::Form::Reseller::IcalTimeSet;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

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
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of time definitions with a number of optional and mandatory keys.']
    },
);

has_field 'times.id' => (
    type => 'Hidden',
);

has_field 'times.start' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
    label => 'Start',
    required => 1,
);
has_field 'times.end' => (
    type => '+NGCP::Panel::Field::DateTimePicker',
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
    type => '+NGCP::Panel::Field::DateTimePicker',
);
has_field 'times.count' => (
    type => 'PosInteger',
    label => 'Count',
);
has_field 'times.interval' => (
    type => 'PosInteger',
    label => 'Interval',
);
has_field 'times.bysecond' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By second',
    min_value => 0,
    max_value => 60,
);
has_field 'times.byminute' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By minute',
    min_value => 0,
    max_value => 59,
);
has_field 'times.byhour' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By hour',
    min_value => 0,
    max_value => 60,
);
has_field 'times.byday' => (
    type => 'Text', # (\+|-)?\d*(MO|DI|MI|DO|FR|SA|SU)
    label => 'By day',
    # example: 5FR (means fifth friday)
);
has_field 'times.bymonthday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By month day',
    min_value => 1,
    max_value => 31,
    plusminus => 1,
);
has_field 'times.byyearday' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By year day',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
);
has_field 'times.byweekno' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By week number',
    min_value => 1,
    max_value => 53,
);
has_field 'times.bymonth' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By month',
    min_value => 1,
    max_value => 12,
);
has_field 'times.bysetpos' => (
    type => '+NGCP::Panel::Field::IntegerList',
    label => 'By set position',
    min_value => 1,
    max_value => 366,
    plusminus => 1,
);
has_field 'times.comment' => (
    type => 'Text',
    label => 'Comment',
);
has_field 'times.rm' => (
    type => 'RmElement',
    value => 'Remove Set',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'times_add' => (
    type => 'AddElement',
    repeatable => 'times',
    value => 'Add another Set',
    element_class => [qw/btn btn-primary pull-right/],
);


has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id name times times_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);


1;

# vim: set tabstop=4 expandtab:
