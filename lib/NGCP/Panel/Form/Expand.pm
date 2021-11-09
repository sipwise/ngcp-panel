package NGCP::Panel::Form::Expand;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Wrapper::None;
extends 'HTML::FormHandler';

has '+widget_wrapper' => ( default => 'None' );

sub build_render_list {[]}

has_field 'billing_profile_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::BillingProfiles',
        },
    },
);

has_field 'contact_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::CustomerContacts',
        },
    },
);

has_field 'contract_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Contracts',
        },
    },
);

has_field 'customer_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Customers',
        },
    },
);

has_field 'domain_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class  => 'NGCP::Panel::Role::API::Domains',
        },
    },
);

has_field 'reseller_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Resellers',
        },
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Subscribers',
            remove_fields => [qw(password webpassword)],
        },
    },
);

1;
