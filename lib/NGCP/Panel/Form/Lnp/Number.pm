package NGCP::Panel::Form::Lnp::Number;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'lnp_provider' => (
    type => '+NGCP::Panel::Field::LnpCarrier',
    label => 'LNP Carrier',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The LNP carrier this number is ported to.']
    },
);

has_field 'number' => (
    type => 'Text',
    required => 1,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ported number. Must be unique across LNP carriers.']
    },
);

has_field 'routing_number' => (
    type => 'Text',
    required => 0,
    maxlength => 31,
    element_attr => {
        rel => ['tooltip'],
        title => ['An optional routing number replacing the ported number.']
    },
);


has_field 'start' => (
    type => '+NGCP::Panel::Field::DatePicker',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The optional date when the porting gets active in format YYYY-MM-DD.']
    },
);

has_field 'end' => (
    type => '+NGCP::Panel::Field::DatePicker',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The optional date when the porting gets inactive again in format YYYY-MM-DD.']
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
    render_list => [qw/lnp_provider number routing_number start end/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_number {
    my ( $self, $field ) = @_;

    unless($field->value =~ /^\d+$/) {
        $field->add_error($field->label . " must be a valid E164 number");
    }
    return;
}

1;
# vim: set tabstop=4 expandtab:
