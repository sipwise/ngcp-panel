package NGCP::Panel::Form::TimeSet;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
);

has_field 'period' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'period.id' => (
    type => 'Hidden',
);

has_field 'period.row' => (
    type => 'Compound',
    label => 'Period',
    do_label => 1,
    tags => {
        before_element => '<div class="ngcp-timeset-row">',
        after_element => '</div>',
    },
);

has_field 'period.row.year' => (
    type => 'Compound',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-timeset-widget">',
        after_element => '</div>',
    },
);
has_field 'period.row.year.from' => (
    type => 'Year',
    label => 'Year',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);
has_field 'period.row.year.to' => (
    type => 'Year',
    label => 'through',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);

has_field 'period.row.month' => (
    type => 'Compound',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-timeset-widget">',
        after_element => '</div>',
    },
);
has_field 'period.row.month.from' => (
    type => 'MonthName',
    label => 'Month',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);
has_field 'period.row.month.to' => (
    type => 'MonthName',
    label => 'through',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);

has_field 'period.row.mday' => (
    type => 'Compound',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-timeset-widget">',
        after_element => '</div>',
    },
);
has_field 'period.row.mday.from' => (
    type => 'MonthDay',
    label => 'Day',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);
has_field 'period.row.mday.to' => (
    type => 'MonthDay',
    label => 'through',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);

has_field 'period.row.wday' => (
    type => 'Compound',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-timeset-widget">',
        after_element => '</div>',
    },
);
has_field 'period.row.wday.from' => (
    type => 'Weekday',
    label => 'Weekday',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);
has_field 'period.row.wday.to' => (
    type => 'Weekday',
    label => 'through',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);

has_field 'period.row.hour' => (
    type => 'Compound',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-timeset-widget">',
        after_element => '</div>',
    },
);
has_field 'period.row.hour.from' => (
    type => 'Hour',
    label => 'Hour',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);
has_field 'period.row.hour.to' => (
    type => 'Hour',
    label => 'trough',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);

has_field 'period.row.minute' => (
    type => 'Compound',
    do_label => 0,
    tags => {
        before_element => '<div class="ngcp-timeset-widget">',
        after_element => '</div>',
    },
);
has_field 'period.row.minute.from' => (
    type => 'Minute',
    label => 'Minute',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);
has_field 'period.row.minute.to' => (
    type => 'Minute',
    label => 'through',
    empty_select => '',
    wrapper_class => [qw/hfh-rep-field ngcp-timeset-field/],
);

has_field 'period.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
#    tags => {
#        "data-confirm" => "Delete",
#    },
);


has_field 'period_add' => (
    type => 'AddElement',
    repeatable => 'period',
    value => 'Add another period',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(name period period_add)],
);

has_field 'save' => (
    type => 'Submit',
    do_label => 0,
    value => 'Save',
    element_class => [qw(btn btn-primary)],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw(modal-footer)],
    render_list => [qw(save)],
);

1;

# vim: set tabstop=4 expandtab:
