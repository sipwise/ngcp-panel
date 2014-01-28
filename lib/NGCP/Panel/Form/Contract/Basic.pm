package NGCP::Panel::Form::Contract::Basic;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'contact' => (
    type => '+NGCP::Panel::Field::Contact',
    label => 'Contact',
    validate_when_empty => 1,
);

has_field 'billing_profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    validate_when_empty => 1,
);

has_field 'status' => (
    type => 'Select',
    required => 1,
    label => 'Status',
    options => [ 
        { label => 'active', value => 'active' },
        { label => 'pending', value => 'pending' },
        { label => 'locked', value => 'locked' },
        { label => 'terminated', value => 'terminated' },
    ],
);

has_field 'external_id' => (
    type => 'Text',
    label => 'External #',
    required => 0,
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
    render_list => [qw/contact billing_profile status external_id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
