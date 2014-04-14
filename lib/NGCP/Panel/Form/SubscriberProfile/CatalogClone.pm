package NGCP::Panel::Form::SubscriberProfile::CatalogClone;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    required => 1,
    label => 'New Name',
);

has_field 'description' => (
    type => 'Text',
    required => 0,
    label => 'New Description',
);

has_field 'clone' => (
    type => 'Submit',
    value => 'Clone',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name description/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/clone/],
);

1;

# vim: set tabstop=4 expandtab:
