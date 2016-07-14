package NGCP::Panel::Form::MailToFax::SecretKey;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use NGCP::Panel::Utils::Form;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'secret_key' => (
    type => 'Text',
    label => 'Secret Key',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enable strict mode that requires all mail2fax emails to have the secret key as the very first line of the email + an empty line. The key is removed from the email once matched.']
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
    render_list => [qw/secret_key/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
