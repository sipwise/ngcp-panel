package NGCP::Panel::Field::E164Alias;
use HTML::FormHandler::Moose;
use NGCP::Panel::Field::E164;
extends 'NGCP::Panel::Field::E164';

has_field 'is_devid' => (
    type => 'Boolean',
    required => 0,
    label => 'Is Device ID',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw/hfh-rep-field/],
    order => 98,
    element_attr => {
        rel => ['tooltip'],
        title => ['When selected, a call to this alias number is only sent to registered devices indicating either the alias number or the optional alternative device id during registration in the Display-Name.']
    },
);

has_field 'devid_alias' => (
    type => 'Text',
    required => 0,
    maxlength => 127,
    label => 'Alternative Device ID',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw/hfh-rep-field/],
    order => 99,
    element_attr => {
        rel => ['tooltip'],
        title => ['An optional device id to be configured on a phone, which is associated with this alias number (e.g. "softphone").']
    },
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
