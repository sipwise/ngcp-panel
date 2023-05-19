package NGCP::Panel::Form::Customer::PbxGroup;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxGroupBase';

has_field 'username' => (
    type => 'Text',
    required => 1,
    label => 'Name',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/username pbx_extension pbx_hunt_policy pbx_hunt_timeout pbx_hunt_cancel_mode/],
);

sub validate_username {
    my ($self, $field) = @_;

    unless($field->value =~ /^[a-zA-Z0-9_\-]+$/) {
        $field->add_error("Invalid group name, must only contain letters, digits, - and _");
    }
}

1;
# vim: set tabstop=4 expandtab:
