package NGCP::Panel::Form::EmergencyMapping::ContainerAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::EmergencyMapping::Container';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id to assign this emergency mapping container to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name/],
);

1;
# vim: set tabstop=4 expandtab:
