package NGCP::Panel::Form::Customer::PbxGroup;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    required => 1,
    label => 'Name',
);

has_field 'extension' => (
    type => 'Text',
    required => 1,
    label => 'Extension',
);

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
    render_list => [qw/name extension hunt_policy hunt_policy_timeout/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate_name {
    my ($self, $field) = @_;

    unless($field->value =~ /^[a-zA-Z0-9_\-\s]+$/) {
        $field->add_error("Invalid group name, must only contain letters, digits, - and _ and spaces");
    }
}

1;
# vim: set tabstop=4 expandtab:
