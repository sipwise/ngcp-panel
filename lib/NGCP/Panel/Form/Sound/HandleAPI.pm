package NGCP::Panel::Form::Sound::HandleAPI;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+enctype' => ( default => 'multipart/form-data');
has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'handle' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The sound handle.'],
    },
);

has_field 'group' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The group this handle belongs to.'],
    },
);

1;

# vim: set tabstop=4 expandtab:
