package NGCP::Panel::Form::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
#sub build_render_list {[qw/submitid fields actions/]}
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

#has_field 'submitid' => (
#    type => 'Hidden'
#);

has_field 'contract' => (
    type => '+NGCP::Panel::Field::Contract',
    label => 'Contract',
    not_nullable => 1,
);

has_field 'name' => (
    type => 'Text',
    required => 1,
);


has_field 'status' => (
    type => '+NGCP::Panel::Field::ResellerStatusSelect',
    required => 1,
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
    render_list => [qw/contract name status/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
