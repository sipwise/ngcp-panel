package NGCP::Panel::Field::BillingProfile;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'billing_profile' => (
    type => '+NGCP::Panel::Field::BillingProfileSelect',
    label => 'Billing Profile',
    required => 1,
);

1;

# vim: set tabstop=4 expandtab:
