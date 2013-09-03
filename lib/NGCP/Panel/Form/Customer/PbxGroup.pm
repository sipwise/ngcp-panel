package NGCP::Panel::Form::Customer::PbxGroup;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxGroupBase';

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

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name extension hunt_policy hunt_policy_timeout/],
);

sub validate_name {
    my ($self, $field) = @_;

    unless($field->value =~ /^[a-zA-Z0-9_\-\s]+$/) {
        $field->add_error("Invalid group name, must only contain letters, digits, - and _ and spaces");
    }
}

1;
# vim: set tabstop=4 expandtab:
