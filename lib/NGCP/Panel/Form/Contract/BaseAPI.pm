package NGCP::Panel::Form::Contract::BaseAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'contact_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

has_field 'billing_profile_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract.']
    },
);

has_field 'billing_profiles' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile / billing network interval schedule used to charge this contract.']
    },
);

has_field 'billing_profiles.id' => (
    type => 'Hidden',
);

has_field 'billing_profiles.profile_id' => (
    type => 'PosInteger',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract.']
    },
);

has_field 'billing_profiles.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_field 'billing_profiles.stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile is revoked.']
    },
);

has_field 'status' => (
    type => 'Select',
    required => 1,
    options => [ 
        { label => 'active', value => 'active' },
        { label => 'pending', value => 'pending' },
        { label => 'locked', value => 'locked' },
        { label => 'terminated', value => 'terminated' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the contract.']
    },
);

has_field 'external_id' => (
    type => 'Text',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['An external id, e.g. provided by a 3rd party provisioning'] 
    },
);

has_field 'subscriber_email_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about subscriber creation.']
    },
);

has_field 'passreset_email_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about password reset.']
    },
);

has_field 'invoice_email_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about invoice.']
    },
);
has_field 'invoice_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The invoice template for invoice generation. If none is assigned, no invoice will be generated for this customer.']
    },
);

has_field 'vat_rate' => (
    type => 'Integer',
    range_start => 0,
    range_end => 100,
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The VAT rate in percentage (e.g. 20).']
    },
);

has_field 'add_vat' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to charge VAT in invoices.']
    },
    default => 0,
);

1;
# vim: set tabstop=4 expandtab:
