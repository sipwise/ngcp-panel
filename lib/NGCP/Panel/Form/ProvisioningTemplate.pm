package NGCP::Panel::Form::ProvisioningTemplate;

use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has 'fields_config' => (is => 'rw');

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body ngcp-modal-preferences/],
);

sub field_list {
    my $self = shift;

    return [] unless $self->ctx;

    my @field_list;
    my $fields_config = $self->fields_config;
    foreach my $field_config (@$fields_config) {
        my %field = %$field_config;
        $field{translate} //= 0;
        push(@field_list,\%field);
    }

    return \@field_list;
}

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $res = 1;

    #todo: support validation expressions ...
    #if (my $field = $self->field( $attribute )) {
    #    if (my $value = $field->value and ...){
    #        $field->add_error($err_msg);
    #    }
    #}
    return $res;
}

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_field 'add' => (
    type => 'Submit',
    value => 'Add',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
    do_wrapper => 0,
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub create_structure {
    my $self = shift;
    my $field_list = shift;

    $self->block('fields')->render_list($field_list);
}

1;