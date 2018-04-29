package NGCP::Panel::Form::Device::Preference;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'attribute' => (
    type => 'Text',
    required => 1,
    label => 'Name',
);

has_field 'label' => (
    type => 'Text',
    required => 1,
    label => 'Label',
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    label => 'Description',
);

has_field 'expose_to_customer' => (
    type => 'Boolean',
    required => 1,
    default => 1,
    label => 'Override on deployed device',
);

has_field 'max_occur' => (
    type => 'PosInteger',
    required => 1,
    label => 'Maximal number of the preference entries',
);

has_field 'data_type' => (
    type => 'Select',
    required => 1,
    label => 'Data type',
    options => [
        { value => '',        label => 'none' },
        { value => 'boolean', label => 'Boolean' },
        { value => 'string',  label => 'String' },
        { value => 'int',     label => 'Integer' },
        { value => 'enum',    label => 'Enum' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Options to lock customer if the monthly limit is exceeded.']
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
    render_list => [qw/attribute expose_to_customer label max_occur description data_type/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
