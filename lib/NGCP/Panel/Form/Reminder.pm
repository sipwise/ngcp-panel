package NGCP::Panel::Form::Reminder;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'time' => (
    type => 'Text',
    label => 'Time',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The time the reminder call is triggered.']
    },
);

has_field 'recur' => (
    type => 'Select',
    label => 'Repeat',
    required => 1,
    options => [
        { label => 'only once', value => 'never' },
        { label => 'on weekdays', value => 'weekdays' },
        { label => 'everyday', value => 'always' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The reminder recurrence (one of never, weekdays, always).']
    },
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
    render_list => [qw/time recur/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_time {
    my ($self, $field) = @_;

    my ($hour, $minute, $second) = split /:/, $field->value;
    $second //= '00';
    unless(defined $hour && int($hour) >= 0 && int($hour) <= 23 &&
           defined $minute && $minute =~ /^[0-5]\d$/) {
        $field->add_error("Invalid time format, must be HH:MM");
    }
    if($second !~ /^[0-5]\d$/) {
        $field->add_error("Invalid time format, must be HH:MM:SS");
    }
}

1;
# vim: set tabstop=4 expandtab:
