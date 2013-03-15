package NGCP::Panel::Field::Contract;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    #type => 'Text',
    label => 'Contract',
    do_label => 1,
    required => 1,
    #widget => '+NGCP::Panel::Widget::DataTable',
    template => 'share/templates/helper/datatables_field.tt',
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
