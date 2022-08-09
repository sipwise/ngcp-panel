package NGCP::Panel::Form::EmergencyMapping::Mapping;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'emergency_container' => (
    type => '+NGCP::Panel::Field::EmergencyMappingContainer',
    label => 'Emergency Mapping Container',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The emergency mapping container this mapping entry belongs to.']
    },
);

has_field 'code' => (
    type => 'Text',
    required => 1,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['The emergency code.']
    },
);

has_field 'prefix' => (
    type => 'Text',
    required => 0,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['An optional emergency prefix the emergency code is mapped to.']
    },
);

has_field 'suffix' => (
    type => 'Text',
    required => 0,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['An optional emergency suffix the emergency code is mapped to.']
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
    render_list => [qw/emergency_container code prefix suffix/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_code {
    my ( $self, $field ) = @_;

    unless($field->value =~ /^\d+$/) {
        $field->add_error($field->label . " must be a number");
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
