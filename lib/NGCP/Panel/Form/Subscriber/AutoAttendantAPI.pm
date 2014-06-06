package NGCP::Panel::Form::Subscriber::AutoAttendantAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {return [qw/submitid fields actions/]}
sub build_form_element_class {return [qw(form-horizontal)]}

has_field 'slots' => (
    type => 'Repeatable',
    label => 'IVR Slots',
);

has_field 'slots.slot' => (
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

has_field 'slots.destination' => (
    type => 'Text',
    label => 'Destination',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The destination for this slot; can be a number, username or full SIP URI.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/slots/],
);

has_field 'subscriber_id' => (
    type => '+NGCP::Panel::Field::PosInteger',
);

sub validate_slots_destination {
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
