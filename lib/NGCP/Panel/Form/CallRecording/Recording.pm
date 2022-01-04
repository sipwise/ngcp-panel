package NGCP::Panel::Form::CallRecording::Recording;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'submitid' => ( type => 'Hidden' );

has_field 'callid' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The SIP call-id of the recorded call.'],
    },
);

has_field 'status' => (
    type => 'Select',
    required => 1,
    options => [
        { name => 'recording', value => 'recording' },
        { name => 'completed', value => 'completed' },
        { name => 'confirmed', value => 'confirmed' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the recording (one of "recording", "completed", "confirmed").'],
    },
);

has_field 'start_time' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The start timestamp of the recording.'],
    },
);

has_field 'end_time' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The end timestamp of the recording.'],
    },
);

has_field 'caller' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
    },
);

has_field 'callee' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
    },
);

1;

# vim: set tabstop=4 expandtab:
