package NGCP::Panel::Form::Contract::ProductOptional;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Basic';

has_field 'product' => (
    type => '+NGCP::Panel::Field::Product',
    label => 'Product',
    required => 0,
);

#has_field 'billing_profiles.product' => (
#    type => '+NGCP::Panel::Field::Product',
#    required => 0,
#    #validate_when_empty => 1,
#    #element_attr => {
#    #    rel => ['tooltip'],
#    #    title => ['The billing profile id used to charge this contract.']
#    #},
#);

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
    render_list => [qw/contact billing_profiles profile_add max_subscribers status external_id invoice_template subscriber_email_template passreset_email_template invoice_email_template vat_rate add_vat/],
);

1;
# vim: set tabstop=4 expandtab:
