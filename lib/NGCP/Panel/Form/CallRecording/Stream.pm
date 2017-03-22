package NGCP::Panel::Form::CallRecording::Stream;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'submitid' => ( type => 'Hidden' );

has_field 'recording_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The id of the recording session.'],
    },
);

has_field 'type' => (
    type => 'Select',
    required => 1,
    options => [
        { name => 'mixed', value => 'mixed' },
        { name => 'single', value => 'single' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The mixing type of the stream (one of "single", "mixed").'],
    },
);

has_field 'format' => (
    type => 'Select',
    required => 1,
    options => [
        { name => 'wav', value => 'wav' },
        { name => 'mp3', value => 'mp3' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The encoding format of the stream (one of "wav", "mp3").'],
    },
);

has_field 'sample_rate' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The sample rate of the stream (e.g. "8000" for 8000Hz).'],
    },
);

has_field 'channels' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of channels in the stream (e.g. 1 for mono, 2 for stereo).'],
    },
);

has_field 'start_time' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The start timestamp of the recording stream.'],
    },
);

has_field 'end_time' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The end timestamp of the recording stream.'],
    },
);

1;

# vim: set tabstop=4 expandtab:
