package NGCP::Panel::Form::Contract::ProductOptional;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Basic';

has_field 'product' => (
    type => '+NGCP::Panel::Field::Product',
    label => 'Product',
    required => 0,
);

has_field 'max_subscribers' => (
    type => 'PosInteger',
    label => 'Max Subscribers',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Optionally set the maximum number of subscribers for this contract. Leave empty for unlimited.']
    },
);


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile product max_subscribers status external_id/],
);

1;
# vim: set tabstop=4 expandtab:
