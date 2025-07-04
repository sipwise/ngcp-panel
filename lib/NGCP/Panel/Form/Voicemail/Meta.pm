package NGCP::Panel::Form::Voicemail::Meta;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'Subscriber ID',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber id the message belongs to.']
    },
);

has_field 'duration' => (
    type => 'PosInteger',
    label => 'Duration',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The duration of the message.']
    },
);

has_field 'time' => (
    type => 'Text',
    label => 'Time',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The time the message was recorded.']
    },
);

has_field 'caller' => (
    type => 'Text',
    label => 'Caller',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The caller ID who left the message.']
    },
);

has_field 'folder' => (
    type => 'Select',
    label => 'Folder',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The folder the message is currently in (one of INBOX, Old, Work, Friends, Family, Cust1-Cust6)']
    },
    options => [
        { label => 'INBOX', value => 'INBOX' },
        { label => 'Old', value => 'Old' },
        { label => 'Work', value => 'Work' },
        { label => 'Friends', value => 'Friends' },
        { label => 'Family', value => 'Family' },
        { label => 'Cust1', value => 'Cust1' },
        { label => 'Cust2', value => 'Cust2' },
        { label => 'Cust3', value => 'Cust3' },
        { label => 'Cust4', value => 'Cust4' },
        { label => 'Cust5', value => 'Cust5' },
        { label => 'Cust6', value => 'Cust6' },
    ]
);

has_field 'transcript_status' => (
    type => 'Select',
    required => 1,
    options => [
        { name => 'none', value => 'none' },
        { name => 'pending', value => 'pending' },
        { name => 'done', value => 'done' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the speech-to-text transcription.'],
    },
);

has_field 'transcript' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The speech-to-text transcription.'],
    },
);

1;
# vim: set tabstop=4 expandtab:
