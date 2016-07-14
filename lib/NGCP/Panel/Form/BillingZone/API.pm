package NGCP::Panel::Form::BillingZone::API;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::BillingZone';

has_field 'billing_profile_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile this billing zone belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/billing_profile_id zone detail/],
);

1;
# vim: set tabstop=4 expandtab:
