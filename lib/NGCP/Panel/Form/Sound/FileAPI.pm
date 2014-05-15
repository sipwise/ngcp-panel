package NGCP::Panel::Form::Sound::FileAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+enctype' => ( default => 'multipart/form-data');
has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'loopplay' => (
    type => 'Boolean',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Play file in a loop.'],
    },
);

has_field 'filename' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The filename of the sound file (for informational purposes only).'],
    },
);

has_field 'set_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The sound set the sound file belongs to.'],
    },
);

has_field 'handle' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The sound handle when to play this sound file.'],
    },
);

1;

# vim: set tabstop=4 expandtab:
