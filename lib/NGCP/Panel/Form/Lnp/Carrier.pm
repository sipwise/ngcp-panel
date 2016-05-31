package NGCP::Panel::Form::Lnp::Carrier;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['A human readable name of the LNP carrier.']
    },
);

has_field 'prefix' => (
    type => 'Text',
    required => 1,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['The routing prefix assigned to this LNP carrier.']
    },
);

has_field 'authoritative' => (
    type => 'Boolean',
    label => 'Authoritative',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['If active, and the number is not assigned to a local subscriber, calls to this number are rejected with 404 Not Found.']
    },
);

has_field 'skip_rewrite' => (
    type => 'Boolean',
    label => 'Skip Rewrite',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['If active, no LNP rewrite rules will be applied after the LNP lookup.']
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
    render_list => [qw/name prefix authoritative skip_rewrite/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
