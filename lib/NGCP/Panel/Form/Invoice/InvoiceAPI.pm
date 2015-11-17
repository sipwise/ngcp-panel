package NGCP::Panel::Form::Invoice::InvoiceAPI;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

has_field 'customer_id' => (
    type => 'PosInteger',
    label => 'Customer',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The customer this invoice belongs to.']
    },
);

has_field 'serial' => (
    type => 'Text',
    label => 'Serial',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The invoice serial number.']
    },
);

has_field 'period_start' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'Invoice Period Start',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The start of the invoice period.']
    },
);

has_field 'period_end' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'Invoice Period End',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The end of the invoice period.']
    },
);

has_field 'amount_net' => (
    type => 'Money',
    label => 'Net Amount',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The net amount of the invoice in USD, EUR etc.']
    },
);

has_field 'amount_vat' => (
    type => 'Money',
    label => 'VAT Amount',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The vat amount of the invoice in USD, EUR etc.']
    },
);

has_field 'amount_total' => (
    type => 'Money',
    label => 'Total Amount',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The vat amount of the invoice in USD, EUR etc.']
    },
);

has_field 'sent_date' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'Invoice Period Start',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The date the invoice has been sent by email or null if not sent.']
    },
);

1;

# vim: set tabstop=4 expandtab:
