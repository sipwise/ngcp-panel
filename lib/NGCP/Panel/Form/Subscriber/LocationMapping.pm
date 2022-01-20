package NGCP::Panel::Form::Subscriber::LocationMapping;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'subscriber_id' => (
    type => 'Hidden',
    required => 0,
);

has_field 'location' => (
    type => 'Text',
    label => 'Location URI',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Location entry SIP-URI.']
    },
);

has_field 'caller_pattern' => (
    type => 'Text',
    label => 'Caller Pattern',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller Pattern']
    },
);

has_field 'callee_pattern' => (
    type => 'Text',
    label => 'Callee Pattern',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Callee Pattern']
    },
);

has_field 'mode' => (
    type => 'Select',
    label => 'Mode',
    required => 1,
    options => [
        { label => 'Add', value => 'add' },
        { label => 'Replace', value => 'replace' },
        { label => 'Offline', value => 'offline' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The location lookup mode']
    },
);

has_field 'to_username' => (
    type => 'Text',
    label => 'To username',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Replace To username with the value']
    },
);

has_field 'external_id' => (
    type => 'Text',
    label => 'External Id',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['External Id value']
    },
);

has_field 'enabled' => (
    type => 'Boolean',
    label => 'Enabled',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enables the entry']
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
    render_list => [qw/subscriber_id location caller_pattern callee_pattern mode to_username external_id enabled/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
