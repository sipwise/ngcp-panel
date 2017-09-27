package NGCP::Panel::Form::Conversation::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    label => 'The original conversation record id - cdr id/voicemail id/sms id/fax journal record id/prosody message archive mgmt (mam) record id.',
    required => 1,
);

has_field 'start_time' => (
    type => 'Text',
    label => 'The timestamp of the conversation event.',
    required => 1,
);

has_field 'type' => (
    type => 'Text',
    label => 'The conversation event type: call/voicemail/sms/fax/xmpp.',
    required => 1,
);

has_field 'status' => (
    type => 'Text',
    label => 'Status of the conversation.',
    required => 1,
);

has_field 'caller' => (
    type => 'Text',
    label => 'Conversation initiator.',
    required => 1,
);

has_field 'callee' => (
    type => 'Text',
    label => 'Conversation receiver.',
    required => 1,
);

has_field 'direction' => (
    type => 'Text',
    label => 'Conversation direction.',
    required => 1,
);

has_field 'duration' => (
    type => 'Text',
    label => 'Conversation duration.',
    required => 1,
);

has_field 'call_type' => (
    type => 'Text',
    label => 'Type of the call event.',
    required => 0,
);

1;
