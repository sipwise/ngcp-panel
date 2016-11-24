package NGCP::Panel::Form::Event::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden'
);

has_field 'type' => (
    type => 'Text',
    label => 'The event type.',
    required => 1,
);

#has_field 'type' => (
#    type => 'Select',
#    label => 'The top-up request type.',
#    options => [
#        { value => 'cash', label => 'Cash top-up' },
#        { value => 'voucher', label => 'Voucher top-up' },
#    ],
#    required => 1,
#);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'The subscriber the event is related to.',
    required => 1,
);

has_field 'old_status' => (
    type => 'Text',
    label => 'Status information before the event, if applicable.',
    required => 0,
);

has_field 'new_status' => (
    type => 'Text',
    label => 'Status information after the event, if applicable.',
    required => 0,
);

has_field 'timestamp' => (
    type => '+NGCP::Panel::Field::DateTime',
    label => 'The timestamp of the event.',
    required => 1,
);

1;
