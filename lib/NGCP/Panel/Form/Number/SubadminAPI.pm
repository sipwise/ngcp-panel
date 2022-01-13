package NGCP::Panel::Form::Number::SubadminAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'cc' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['Country Code, e.g. 1 for US or 43 for Austria (read-only)']
    },
);

has_field 'ac' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['Area Code, e.g. 212 for NYC or 1 for Vienna (read-only)']
    },
);

has_field 'sn' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['Subscriber Number, e.g. 12345678 (read-only)']
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The id of the subscriber the number is assigned to.']
    },
);

has_field 'is_primary' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether the number is a primary number or not (read-only).']
    },
);

has_field 'is_devid' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['When selected, it is possible to register with the alias and receive calls directed to the alias only']
    },
);

1;
# vim: set tabstop=4 expandtab:
