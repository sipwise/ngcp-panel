package NGCP::Panel::Form::Sound::SoundSetAPIBase;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Sound::LoadDefaultBase';

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the sound set'],
    },
);

has_field 'description' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The description of the sound set'],
    },
);

has_field 'contract_default' => (
    type => 'Boolean',
    label => 'Default for Subscribers',
    element_attr => {
        rel => ['tooltip'],
        title => ['If active (and a customer is selected), this sound set is used for all existing and new subscribers within this customer if no specific sound set is specified for the subscribers'],
    },
);

has_field 'copy_from_default' => (
    type => 'Boolean',
    label => 'Use system default sound files',
    required => 0,
);


1;