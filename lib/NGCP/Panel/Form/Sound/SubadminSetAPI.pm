package NGCP::Panel::Form::Sound::SubadminSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Sound::SoundSetBase';

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name description contract_default copy_from_default language loopplay override/],
);

# TODO: inheritance?

1;
