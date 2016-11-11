package NGCP::Panel::Form::SMSAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Field::BillingZone;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden',
    element_attr => {
        rel => ['tooltip'],
        title => ['The internal id in the sms journal'],
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber id this journal entry belongs to'],
    },
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { value => 'in', label => 'inbound' },
        { value => 'out', label => 'outbound' },
    ],
    default => 'out', # FYI, default is not considered with API
    required => 0,  # should be "1" actually, see above
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether the logged message is sent or received'],
    },
);

has_field 'caller' => (
    type => 'Text',
    required => 0,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Our CLI in case of sent messages. Must be valid according to the preferences allowed_clis, user_cli, cli'],
    },
);

has_field 'callee' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['A valid CLI in the E164 format'],
    },
);

has_field 'text' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The content of the message'],
    },
);

has_field 'status' => (
    type => 'Text', # Readonly
    required => 0,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether the message has been sent successfully'],
    },
);

has_field 'reason' => (
    type => 'Text', # Readonly
    required => 0,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['An error message in case of a failed transmission'],
    },
);

has_field 'time' => (
    type => '+NGCP::Panel::Field::DateTime', # Readonly
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The timestamp of the message'],
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
    render_list => [qw/id subscriber_id direction caller callee text status reason/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
