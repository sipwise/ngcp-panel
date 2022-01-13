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
        title => ['When selected, it is possible to register with the alias and receive calls directed to the alias only']
    },
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
