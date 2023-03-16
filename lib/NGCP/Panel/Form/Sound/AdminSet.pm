package NGCP::Panel::Form::Sound::AdminSet;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Sound::ResellerSet';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller this sound set belongs to.'],
    },
);

has_field 'parent' => (
    type => '+NGCP::Panel::Field::ParentSoundSetAdmin',
    label => 'Parent',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Parent sound set. If used, missing sound of the current sound set will used from the parent one (except for those with use_parent = 0)'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller contract name description expose_to_customer contract_default parent/],
);

1;

# vim: set tabstop=4 expandtab:
