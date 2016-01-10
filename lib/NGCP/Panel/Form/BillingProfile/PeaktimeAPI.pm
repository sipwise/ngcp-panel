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

1;
# vim: set tabstop=4 expandtab:
