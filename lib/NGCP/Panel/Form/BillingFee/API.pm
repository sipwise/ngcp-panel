package NGCP::Panel::Form::BillingFee::API;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::BillingFee';

has_field 'billing_profile_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile this billing fee belongs to.']
    },
);

has_field 'purge_existing' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['If fees are uploaded via text/csv bulk upload, this option defines whether to purge any existing fees for the given billing profile before inserting the new ones.']
    },
    default => 0,
);


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/purge_existing billing_zone billing_profile_id match_mode source destination direction
        onpeak_init_rate onpeak_init_interval onpeak_follow_rate
        onpeak_follow_interval offpeak_init_rate offpeak_init_interval
        offpeak_follow_rate offpeak_follow_interval onpeak_use_free_time offpeak_use_free_time
        onpeak_extra_rate onpeak_extra_second offpeak_extra_rate offpeak_extra_second aoc_pulse_amount_per_message
        /],
);

1;
# vim: set tabstop=4 expandtab:
