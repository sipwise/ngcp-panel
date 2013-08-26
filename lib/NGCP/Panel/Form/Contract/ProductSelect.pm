package NGCP::Panel::Form::Contract::ProductSelect;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Basic';

has_field 'product' => (
    type => '+NGCP::Panel::Field::Product',
    label => 'Product',
    not_nullable => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/product contact billing_profile status external_id/],
);

1;
# vim: set tabstop=4 expandtab:
