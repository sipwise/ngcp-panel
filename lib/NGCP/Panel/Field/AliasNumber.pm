package NGCP::Panel::Field::AliasNumber;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Repeatable';


#has 'label' => ( default => 'E164 Number');

has_field 'id' => (
    type => 'Hidden',
);

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164', 
    order => 97,
    required => 0,
    label => 'Alias Number',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

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

has_field 'rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/e164 is_devid/ ],
);


no Moose;
1;

# vim: set tabstop=4 expandtab:
