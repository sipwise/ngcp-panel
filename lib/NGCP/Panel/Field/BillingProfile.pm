package NGCP::Panel::Field::BillingProfile;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'foo' => (
    type => '+NGCP::Panel::Field::BillingProfileSelect',
    label => 'Billing Profile',
    required => 1,
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Billing Profile',
    element_attr => { onclick => 'window.location=\'/billingprofile/create\'' },
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
