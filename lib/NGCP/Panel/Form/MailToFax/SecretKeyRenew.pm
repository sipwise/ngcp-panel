package NGCP::Panel::Form::MailToFax::SecretKeyRenew;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use NGCP::Panel::Utils::Form;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'secret_key_renew' => (
    type => 'Select',
    options => [
        { label => 'Never', value => 'never' },
        { label => 'Daily', value => 'daily' },
        { label => 'Weekly', value => 'weekly' },
        { label => 'Monthly', value => 'monthly' },
    ],
    label => 'Secret Renew Interval ',
    default => 'never',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Interval when the secret key is automatically renewed.']
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
    render_list => [qw/secret_key_renew/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
