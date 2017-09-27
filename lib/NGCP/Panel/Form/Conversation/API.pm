package NGCP::Panel::Form::Conversation::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    label => 'The original conversation record id - cdr id/voicemail id/sms id/fax journal record id/prosody message archive mgmt (mam) record id.',
    required => 1,
);

has_field 'call_id' => (
    type => 'Text',
    label => 'Call id.',
    required => 1,
);

has_field 'call_type' => (
    type => 'Text',
    label => 'One of the "call","cfu","cft","cfb","cfna".',
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
    label => 'Status of the conversation. Possible values are: "ok","busy","noanswer","cancel","offline","timeout","other".',
    required => 1,
);

has_field 'rating_status' => (
    type => 'Text',
    label => 'Status of the rate processing for the conversation. Possible values are: "unrated","ok","failed".',
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

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'Subscriber who can manage fax record.',
    required => 0,
);

has_field 'pages' => (
    type => 'Integer',
    label => 'Number of the pages in the fax document.',
    required => 0,
);

has_field 'filename' => (
    type => 'Text',
    label => 'Filename of the fax document.',
    required => 0,
);

#has_field 'dir' => (
#    type => 'Text',
#    label => 'Directory of the voicemail placement.',
#    required => 0,
#);

has_field 'folder' => (
    type => 'Text',
    label => 'The folder the message is currently in (one of INBOX, Old, Work, Friends, Family, Cust1-Cust6).',
    required => 0,
);

has_field 'context' => (
    type => 'Text',
    label => 'TBD',
    required => 0,
);

has_field 'voicemail_subscriber_id' => (
    type => 'Integer',
    label => 'The subscriber id the message belongs to.',
    required => 0,
);



#caller_subscriber

#'pages' => 0,
#'caller_uuid' => 'a4728f99-d4bf-4ac0-a231-7cda2c7be300',
#'filename' => 'ec71ccd2-895f-4f70-a1d7-5f6c54888239.tif',
#'time' => '1508336175.000',
#'id' => 1,
#'type' => 'fax',
#'timestamp' => '1508336175.000',
#'reason' => ' / SIP 480 Offline [3/3]',
#'direction' => 'out',
#'status' => 'FAILED',
#'sid' => 'ec71ccd2-895f-4f70-a1d7-5f6c54888239',
#'quality' => '0x0',
#'signal_rate' => 0,
#'callee_uuid' => '13e67a16-b7ab-44f2-95bb-cb15cb0ec657',
#'caller' => '222111444201'

1;
