package NGCP::Panel::Form::Contract::BasicWithContact;

use HTML::FormHandler::Moose;
use Storable qw();
extends 'NGCP::Panel::Form::Contract::Basic';

has_field 'contact' => (
    type => '+NGCP::Panel::Field::Contact',
    label => 'Contact',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile status external_id subscriber_email_template passreset_email_template invoice_email_template invoice_template vat_rate add_vat/],
);

1;
# vim: set tabstop=4 expandtab:
