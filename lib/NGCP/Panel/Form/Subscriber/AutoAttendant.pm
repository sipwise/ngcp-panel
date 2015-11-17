package NGCP::Panel::Form::Subscriber::AutoAttendant;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'slot' => (
    type => 'Repeatable',
    label => 'IVR Slots',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
);

has_field 'slot.id' => (
    type => 'Hidden',
);

has_field 'slot.choice' => (
    type => 'Select',
    label => 'Key',
    required => 1,
    options => [
        { label => '0', value => 0 },
        { label => '1', value => 1 },
        { label => '2', value => 2 },
        { label => '3', value => 3 },
        { label => '4', value => 4 },
        { label => '5', value => 5 },
        { label => '6', value => 6 },
        { label => '7', value => 7 },
        { label => '8', value => 8 },
        { label => '9', value => 9 },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The IVR key to press for this destination'],
    },
);

has_field 'slot.destination' => (
    type => 'Text',
    label => 'Destination',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The destination for this slot; can be a number, username or full SIP URI.'],
    },
);

has_field 'slot.rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'slot_add' => (
    type => 'AddElement',
    repeatable => 'slot',
    value => 'Add another Slot',
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
    render_list => [qw/slot slot_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_slot_destination {
    my ($self, $field) = @_;

    $field->clear_errors;
    # TODO: proper SIP URI check
    unless($field->value =~ /^(sip:)?[^\@]+(\@.+)?$/) {
        my $err_msg = 'Invalid destination, must be number, username or SIP URI';
        $field->add_error($err_msg);
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
