package NGCP::Panel::Form::CustomerFraudEvents::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    label => 'ID',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['ID of the period.']
    },
);

has_field 'contract_id' => (
    type => 'PosInteger',
    label => 'Contract',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Contract ID of the customer/system contract causing the fraud event.']
    },
);

has_field 'interval' => (
    type => 'Select',
    label => 'Interval',
    required => 1,
    options => [
        { label => 'current day', value => 'day' },
        { label => 'current month', value => 'month' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Period of the fraud event.']
    },
);

#has_field 'interval_date' => (
#    type => 'Text',
#    label => 'Interval Date',
#    required => 1,
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['Interval date of the fraud events.']
#    },
#);

has_field 'type' => (
    type => 'Select',
    label => 'Type',
    required => 1,
    options => [
        { label => 'contract fraud preference', value => 'account_limit' },
        { label => 'billing_profile', value => 'profile_limit' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Origin of fraud setting in effect.']
    },
);

has_field 'interval_cost' => (
    type => 'Float',
    label => 'Interval cost',
    precision => '2',
    size => '9',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Cost within the interval.']
    },
);

has_field 'interval_limit' => (
    type => 'Float',
    label => 'Interval limit',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Cost limit for the interval.']
    },
);

has_field 'interval_lock' => (
    type => '+NGCP::Panel::Field::SubscriberLockSelect',
    label => 'Interval Lock',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Lock level to apply.']
    },
);

has_field 'use_reseller_rates' => (
    type => 'Integer',
    label => 'Use reseller rates',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether the reseller rates were used for interval_cost or not.']
    },
);

has_field 'interval_notify' => (
    type => 'Text',
    label => 'Notify Email',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Email used for this notification.']
    },
);

has_field 'notify_status' => (
    type => 'Select',
    label => 'Notify Status',
    required => 1,
    options => [
        { label => 'new', value => 'new' },
        { label => 'notified', value => 'notified' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Status of the notification. \'new\' events are pending to be sent.']
    },
);

has_field 'notified_at' => (
    type => 'Text',
    label => 'Notified at',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['When the last email notification was sent.']
    },
);

1;

=head1 NAME

NGCP::Panel::Form::CustomerFraudEvents::Reseller

=head1 DESCRIPTION

=head1 METHODS

=head1 AUTHOR

Kirill Solomko

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
