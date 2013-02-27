package NGCP::Panel::Form::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

sub build_render_list {[qw/fields actions/]}

sub build_form_tags {
    { error_class => 'label label-secondary', }
}

sub build_form_element_class {
    [qw/form-horizontal/]
}

has_field 'id' => (
    type => 'PosInteger',
    wrapper_class => [qw/field control-group/],
    label_class => [qw/control-label/],
    error_class => [qw/error/],
    required => 1,
    disabled => 1,
);

has_field 'name' => (
    type => 'Text',
    wrapper_class => [qw/field control-group/],
    label_class => [qw/control-label/],
    error_class => [qw/error/],
    required => 1,
);

has_field 'contract_id' => (
    type => 'Integer',
    wrapper_class => [qw/field control-group/],
    label_class => [qw/control-label/],
    error_class => [qw/error/],
    required => 1,
);

has_field 'status' => (
    type => 'Text',
    wrapper_class => [qw/field control-group/],
    label_class => [qw/control-label/],
    error_class => [qw/error/],
    required => 1,
);

has_field 'cancel' => (
    type => 'Button',
    value => 'Cancel',
    element_class => [qw/btn/],
    element_attr => { 
        onclick => "javascript:document.location.href='/reseller'",
    },
    label => '',
    tags => { wrapper_tag => 'span' },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
    tags => { wrapper_tag => 'span' },
);

has_block 'fields' => (
    tag => 'div', 
    class => [qw/modal-body/],
    render_list => [qw/id contract_id name status/],
);
has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/cancel save/],
);

1;
# vim: set tabstop=4 expandtab:
