package NGCP::Panel::Form::Contract;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Model::DBIC';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'contract' => (
    type => 'Compound',
);

has_field 'contract.contact' => (
    type => '+NGCP::Panel::Field::Contact',
    label => 'Contact',
    not_nullable => 1,
);

has_field 'billing_profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    not_nullable => 1,
);


has_field 'contract.status' => (
    type => '+NGCP::Panel::Field::ContractStatusSelect',
    not_nullable => 1,
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
    render_list => [qw/contract.contact billing_profile contract.status/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
