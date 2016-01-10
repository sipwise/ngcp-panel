package NGCP::Panel::Form::BillingProfile::PeaktimeAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::BillingProfile::Admin';

has_field 'peaktime_weekdays' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['The \'weekday\' peak-time schedule for this billing profile. It is represented by an array of objects, each containing the keys "weekday" (0 .. Monday, 6 .. Sunday), "start" (HH:mm:ss) and "stop" (HH:mm:ss). Each time range provided determines when to use a fee\'s offpeak rates.']
    },
);

has_field 'peaktime_weekdays.id' => (
    type => 'Hidden',
);

has_field 'peaktime_weekdays.weekday' => (
    type => 'Integer',
    required => 1,
);

has_field 'peaktime_weekdays.start' => (
    type => 'Text',
    required => 0,
);

has_field 'peaktime_weekdays.stop' => (
    type => 'Text',
    required => 0,
);

has_field 'peaktime_special' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['The \'special\' peak-time schedule for this billing profile. It is represented by an array of objects, each containing the keys "start" (YYYY-MM-DD HH:mm:ss) and "stop" (YYYY-MM-DD HH:mm:ss). Each time range provided determines when to use a fee\'s offpeak rates.']
    },
);

has_field 'peaktime_special.id' => (
    type => 'Hidden',
);

has_field 'peaktime_special.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 1,
);

has_field 'peaktime_special.stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 1,
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
