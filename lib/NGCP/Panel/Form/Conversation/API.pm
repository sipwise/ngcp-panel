package NGCP::Panel::Form::Conversation::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'type' => (
    type => 'Text',
    label => 'The conversation event type: call/voicemail/sms/fax/xmpp.',
    required => 1,
);

has_field 'id' => (
    type => 'PosInteger',
    label => 'The original conversation record id - cdr id/voicemail id/sms id/fax journal record id/prosody message archive mgmt (mam) record id.',
    required => 1,
);

has_field 'timestamp' => (
    type => 'Text',
    label => 'The timestamp of the conversation event.',
    required => 1,
);

1;
