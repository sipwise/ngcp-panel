package NGCP::Panel::Form::NCOS::SubAdminLevelAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'level' => (
    type => 'Text',
    label => 'Level Name',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The level name']
    },
);

has_field 'description' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The description of the level']
    },
);

1;

# vim: set tabstop=4 expandtab:
