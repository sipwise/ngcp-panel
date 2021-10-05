package NGCP::Panel::Form::MailToFax::ACL;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'acl' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'acl.id' => (
    type => 'Hidden',
);

has_field 'acl.from_email' => (
    type => 'Text',
    label => 'From email',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Accepted email address to allow mail2fax transmission.']
    },
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.received_from' => (
    type => 'Text',
    label => 'Received from IP',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Allow mail2fax emails only to this IP (the IP or hostname is present in the "Received" header).']
    },
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.destination' => (
    type => 'Text',
    label => 'Destination',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Allow mail2fax destination only to this number.']
    },
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.use_regex' => (
    type => 'Boolean',
    label => 'Use Regex',
    default => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enable regex matching for "Received from IP" and "Destination" fields.']
    },
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'acl.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'acl_add' => (
    type => 'AddElement',
    repeatable => 'acl',
    value => 'Add another rule',
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
    render_list => [qw/acl acl_add/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
