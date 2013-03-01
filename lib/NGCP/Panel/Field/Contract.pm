package NGCP::Panel::Field::Contract;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'foo' => (
    type => '+NGCP::Panel::Field::ContractSelect',
    label => 'Contract',
    required => 1,
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contract',
    element_attr => { onclick => 'window.location=\'/contract/create\'' },
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
