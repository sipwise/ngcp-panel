package NGCP::Panel::Field::ContractStatus;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'status' => (
    type => '+NGCP::Panel::Field::ContractStatusSelect',
    label => 'Status',
    required => 1,
);

1;

# vim: set tabstop=4 expandtab:
