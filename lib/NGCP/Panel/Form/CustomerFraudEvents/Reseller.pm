package NGCP::Panel::Form::CustomerFraudEvents::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    label => 'Customer',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Customer that a fraud event belongs to.']
    },
);

has_field 'interval' => (
    type => 'Text',
    label => 'Interval',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Interval of the fraud events.']
    },
);

has_field 'interval_date' => (
    type => 'Text',
    label => 'Interval Date',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Interval date of the fraud events.']
    },
);

has_field 'type' => (
    type => 'Text',
    label => 'Type',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Type of the fraud event.']
    },
);

has_field 'interval_cost' => (
    type => 'Float',
    label => 'Interval cost',
    precision => '3',
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
    type => 'Integer',
    label => 'Interval Lock',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Lock type for the interval.']
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

has_field 'notify_status' => (
    type => 'Text',
    label => 'Notify Status',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Status of the notification.']
    },
);

has_field 'notified_at' => (
    type => 'Text',
    label => 'Notified at',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['When the last related notification was sent.']
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
