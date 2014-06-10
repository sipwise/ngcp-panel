package NGCP::Panel::Form::NCOS::ResellerLevelAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

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

has_field 'mode' => (
    type => 'Select',
    required => 1,
    options => [
        {value => 'whitelist', label => 'whitelist'},
        {value => 'blacklist', label => 'blacklist'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The level mode (one of blacklist, whitelist)']
    },
);

has_field 'description' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The description of the level']
    },
);

has_field 'local_ac' => (
    type => 'Boolean',
    label => 'Include local area code',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to include check for calls to local area code']
    },
);

1;

# vim: set tabstop=4 expandtab:
