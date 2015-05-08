package NGCP::Panel::Form::Contract::ProductOptionalAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::ProductOptional';

has_field 'billing_profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract.']
    },
);

has_field '+billing_profiles' => ( #or override this one to drop the required flag
    required => 0,
);

has_field 'product' => (
    type => '+NGCP::Panel::Field::Product',
    label => 'Product',
    required => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile billing_profiles product max_subscribers status external_id invoice_template subscriber_email_template passreset_email_template invoice_email_template vat_rate add_vat/],
);

1;
# vim: set tabstop=4 expandtab:
