package NGCP::Panel::Form::BillingZone;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'id' => (
    type => 'Hidden'
);

has_field 'zone' => (
    type => 'Text',
    maxlength => 127,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A short name for the zone (e.g. US).']
    },
);

has_field 'detail' => (
    type => 'Text',
    maxlength => 127,
    element_attr => {
        rel => ['tooltip'],
        title => ['The detailed name for the zone (e.g. US Mobile Numbers).']
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id zone detail/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
