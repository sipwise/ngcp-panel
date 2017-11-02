package NGCP::Panel::Form::Administrator::AdminSpecial;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use NGCP::Panel::Utils::Form;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'is_active' => (type => 'Boolean', default => 1);
has_field 'save' => (type => 'Submit', element_class => [qw(btn btn-primary)],);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(is_active)],
);
has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(save)],);

1;
