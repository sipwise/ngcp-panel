package NGCP::Panel::Form::CustomerFraudPreferences::PreferencesAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has_field 'current_fraud_interval_source' => (
    required => 0,
    type => 'Select',
    label => 'Fraud preferences interval source (customer or billing_profile)',
    options => [
        { value => 'customer', label => 'Customer' },
        { value => 'billng_profile', label => 'Billing Profile' },
    ],
);

has_field 'fraud_interval_limit' => (
    type => 'Integer',
    label => 'Fraud detection threshold per month in cents',
);

has_field 'current_fraud_interval_limit' => (
    type => 'Integer',
    required => 0,
    label => 'Current fraud detection threshold per month in cents',
);

has_field 'fraud_interval_lock' => (
    type => 'Select',
    label => 'Lock level',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
        { value => 5, label => 'ported (call forwarding only)' },
    ],
);

has_field 'current_fraud_interval_lock' => (
    type => 'Select',
    required => 0,
    label => 'Current lock level',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
        { value => 5, label => 'ported (call forwarding only)' },
    ],
);

has_field 'fraud_interval_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    maxlength => 255,
    label => 'Comma-separated list of e-mail addresses for notification'
);

has_field 'current_fraud_interval_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    required => 0,
    maxlength => 255,
    label => 'Current comma-separated list of e-mail addresses for notification'
);

has_field 'current_fraud_daily_source' => (
    required => 0,
    type => 'Select',
    label => 'Fraud daily preferences source (customer or billing_profile)',
    options => [
        { value => 'customer', label => 'Customer' },
        { value => 'billng_profile', label => 'Billing Profile' },
    ],
);

has_field 'fraud_daily_limit' => (
    type => 'Integer',
    label => 'Fraud detection threshold per day in cents',
);

has_field 'current_fraud_daily_limit' => (
    type => 'Integer',
    label => 'Current fraud detection threshold per day in cents',
);

has_field 'fraud_daily_lock' => (
    type => 'Select',
    label => 'Daily lock level',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
        { value => 5, label => 'ported (call forwarding only)' },
    ],
);

has_field 'current_fraud_daily_lock' => (
    type => 'Select',
    required => 0,
    label => 'Current daily lock level',
    options => [
        { value => 0, label => 'none' },
        { value => 1, label => 'foreign calls' },
        { value => 2, label => 'all outgoing calls' },
        { value => 3, label => 'incoming and outgoing' },
        { value => 4, label => 'global (including CSC)' },
        { value => 5, label => 'ported (call forwarding only)' },
    ],
);

has_field 'fraud_daily_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    maxlength => 255,
    label => 'Comma-separated list of e-mail addresses for notification'
);

has_field 'current_fraud_daily_notify' => (
    type => '+NGCP::Panel::Field::EmailList',
    required => 0,
    maxlength => 255,
    label => 'Current comma-separated list of e-mail addresses for notification'
);

1;
