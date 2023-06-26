package NGCP::Panel::Form::NCOS::ResellerLevelAPI;

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
    required => 0,
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

has_field 'intra_pbx' => (
    type => 'Boolean',
    label => 'Include Intra PBX Calls within same Customer',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to include check for intra pbx calls within same customer']
    },
);

has_field 'time_set_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The timeset id to use for this level']
    },
);

has_field 'expose_to_customer' => (
    type => 'Boolean',
    label => 'Expose to Customer',
    element_attr => {
        rel => ['tooltip'],
        title => ['Customers can see and use this NCOS Level in their preferences']
    },
);

1;

# vim: set tabstop=4 expandtab:
