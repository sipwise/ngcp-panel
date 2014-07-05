package NGCP::Panel::Form::BillingFee::API;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::BillingFee';
use Moose::Util::TypeConstraints;

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
    render_list => [qw/purge_existing billing_zone source destination direction
        onpeak_init_rate onpeak_init_interval onpeak_follow_rate
        onpeak_follow_interval offpeak_init_rate offpeak_init_interval
        offpeak_follow_rate offpeak_follow_interval use_free_time
        /],
);

1;
# vim: set tabstop=4 expandtab:
