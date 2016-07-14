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

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller contract name description contract_default/],
);

1;

# vim: set tabstop=4 expandtab:
