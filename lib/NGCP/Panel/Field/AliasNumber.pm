package NGCP::Panel::Field::AliasNumber;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Repeatable';


#has 'label' => ( default => 'E164 Number');

has_field 'id' => (
    type => 'Hidden',
);

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164', 
    order => 99,
    required => 0,
    label => 'Alias Number',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);


1;

# vim: set tabstop=4 expandtab:
