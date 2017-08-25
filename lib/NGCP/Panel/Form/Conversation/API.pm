package NGCP::Panel::Form::Conversation::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

#has_field 'id' => (
#    type => 'Hidden'
#);

has_field 'type' => (
    type => 'Text',
    label => 'xxxxxx.',
    required => 1,
);

has_field 'id' => (
    type => 'Text',
    label => 'yyyyyy.',
    required => 1,
);

has_field 'timestamp' => (
    type => 'Text',
    label => 'yyyyyy.',
    required => 1,
);

1;
