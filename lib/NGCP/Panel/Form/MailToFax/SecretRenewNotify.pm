package NGCP::Panel::Form::MailToFax::SecretRenewNotify;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'secret_renew_notify' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'secret_renew_notify.id' => (
    type => 'Hidden',
);

has_field 'secret_renew_notify.destination' => (
    type => 'Text',
    label => 'Notify email',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Destination email to send the secret key renew notification to.']
    },
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'secret_renew_notify.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'secret_renew_notify_add' => (
    type => 'AddElement',
    repeatable => 'secret_renew_notify',
    value => 'Add another notify email',
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
    render_list => [qw/secret_renew_notify secret_renew_notify_add/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
