package NGCP::Panel::Form::CustomerFraudPreferences::PreferencesAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

#has_field 'id' => (
#    type => 'Hidden',
#);

#has_field 'contract_id' => (
#    type => '+NGCP::Panel::Field::PosInteger',
#    required => 1,
#    label => 'The contract id this fraud preference belongs to.',
#);

has_field 'fraud_interval_limit' => (
    type => 'Integer',
    #required => 1,
    label => 'Fraud detection threshold per month in cents.',
);

has_field 'fraud_interval_lock' => (
    type => 'Select',
    label => 'Lock Level',
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
    label => 'Comma-separated list of e-mail addresses for notification.'
);

has_field 'fraud_daily_limit' => (
    type => 'Integer',
    #required => 1,
    label => 'Fraud detection threshold per day in cents.',
);

has_field 'fraud_daily_lock' => (
    type => 'Select',
    label => 'Lock Level',
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
    label => 'Comma-separated list of e-mail addresses for notification.'
);

1;
