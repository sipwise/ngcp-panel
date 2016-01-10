package NGCP::Panel::Form::BillingProfile::PeaktimeAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::BillingProfile::Admin';

has_field 'peaktime_weekdays' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['The peak-time schedule for this billing profile.']
    },
);

has_field 'peaktime_weekdays.id' => (
    type => 'Hidden',
);

has_field 'peaktime_weekdays.weekday' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_field 'peaktime_weekdays.start' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['off-peak begin inclusive.']
    },
);

has_field 'peaktime_weekdays.stop' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['off-peak end inclusive.']
    },
);

has_field 'peaktime_special' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile / billing network interval schedule used to charge this contract can be specified. It is represented by an array of objects, each containing the keys "start", "stop", "profile_id" and "network_id" (/api/customers/ only). When POSTing, it has to contain a single interval with empty "start" and "stop" fields. Only intervals beginning in the future can be updated afterwards. This field is required if the \'profiles\' profile definition mode is used.']
    },
);

has_field 'peaktime_special.id' => (
    type => 'Hidden',
);

has_field 'peaktime_special.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_field 'peaktime_special.stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller handle name prepaid interval_charge interval_free_time interval_free_cash
        fraud_interval_limit fraud_interval_lock fraud_interval_notify
        fraud_daily_limit fraud_daily_lock fraud_daily_notify fraud_use_reseller_rates
        currency id
        status peaktime_weekdays peaktime_special/],
);

1;
# vim: set tabstop=4 expandtab:
