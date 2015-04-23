package NGCP::Panel::Form::BillingProfile::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::BillingProfile::Reseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this profile belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller handle name prepaid interval_charge interval_free_time interval_free_cash 
        fraud_interval_limit fraud_interval_lock fraud_interval_notify
        fraud_daily_limit fraud_daily_lock fraud_daily_notify fraud_use_reseller_rates
        currency id
        status/],
);


1;
# vim: set tabstop=4 expandtab:
