package NGCP::Panel::Form::Reseller;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'contract' => (
    type => '+NGCP::Panel::Field::ResellerContract',
    label => 'Contract',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract used for this reseller.']
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the reseller.']
    },
);


has_field 'status' => (
    type => '+NGCP::Panel::Field::ResellerStatusSelect',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the reseller.']
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
    render_list => [qw/contract name status/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
