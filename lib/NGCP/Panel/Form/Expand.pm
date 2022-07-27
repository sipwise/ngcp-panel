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
            allowed_roles => [qw(admin reseller ccareadmin ccare)],
        },
    },
);

has_field 'contact_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::CustomerContacts',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'contract_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Contracts',
            allowed_roles => [qw(admin)],
        },
    },
);

has_field 'customer_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Customers',
            allowed_roles => [qw(admin reseller ccareadmin ccare)],
        },
    },
);

has_field 'domain_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class  => 'NGCP::Panel::Role::API::Domains',
            allowed_roles => [qw(admin reseller ccareadmin ccare)],
        },
    },
);

has_field 'profile_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::SubscriberProfiles',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'profile_set_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::SubscriberProfileSets',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'reseller_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Resellers',
            allowed_roles => [qw(admin)],
        },
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Subscribers',
            remove_fields => [qw(password webpassword _password _webpassword)],
            allowed_roles => [qw(admin reseller ccareadmin ccare subscriberadmin)],
        },
    },
);

has_field 'package_after_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::ProfilePackages',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'package_before_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::ProfilePackages',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'profile_after_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::SubscriberProfiles',
            allowed_roles => [qw(admin reseller ccareadmin ccare subscriberadmin subscriber)],
        },
    },
);

has_field 'profile_before_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::SubscriberProfiles',
            allowed_roles => [qw(admin reseller ccareadmin ccare subscriberadmin subscriber)],
        },
    },
);

has_field 'contract_balance_after_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::CustomerBalances',
            allowed_roles => [qw(admin reseller ccareadmin ccare)],
        },
    },
);

has_field 'contract_balance_before_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::CustomerBalances',
            allowed_roles => [qw(admin reseller ccareadmin ccare)],
        },
    },
);

has_field 'voucher_id' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Vouchers',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'pbx_group_ids' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Subscribers',
            remove_fields => [qw(password webpassword _password _webpassword)],
            allowed_roles => [qw(admin reseller ccareadmin ccare subscriberadmin subscriber)],
        },
    },
);

has_field 'pbx_groupmember_ids' => (
    type => 'PosInteger',
    element_attr => {
        expand => {
            class => 'NGCP::Panel::Role::API::Subscribers',
            remove_fields => [qw(password webpassword _password _webpassword)],
            allowed_roles => [qw(admin reseller ccareadmin ccare subscriberadmin subscriber)],
        },
    },
);

1;
