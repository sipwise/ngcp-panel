package NGCP::Panel::Form::Customer::PbxGroupBase;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'hunt_policy' => (
    type => 'Select',
    required => 1,
    label => 'Hunting Policy',
    options => [
        { label => 'Serial Ringing', value => 'serial' },
        { label => 'Parallel Ringing', value => 'parallel' },
    ],
    default => 'serial',
);

has_field 'hunt_policy_timeout' => (
    type => 'PosInteger',
    required => 1,
    label => 'Serial Ringing Timeout',
    default => 10,
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
    render_list => [qw/hunt_policy hunt_policy_timeout/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
