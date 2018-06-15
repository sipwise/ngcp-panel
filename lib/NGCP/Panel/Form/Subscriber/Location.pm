package NGCP::Panel::Form::Subscriber::Location;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber::LocationEntry';

use HTML::FormHandler::Widget::Block::Bootstrap;

sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact q socket/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
