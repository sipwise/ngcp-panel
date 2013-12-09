package NGCP::Panel::Form::Administrator::APIGenerate;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
sub build_render_list {[qw(actions)]}

has_field 'key_actions' => (
    type => 'Compound',
    do_label => 0,
    do_wrapper => 1,
    wrapper_class => [qw(row pull-right)],
);

has_field 'key_actions.generate' => (
    type => 'Submit',
    value => 'Generate',
    element_class => [qw(btn btn-primary)],
    wrapper_class => [qw(pull-right)],
);

has_block 'actions' => (tag => 'div', class => [qw(modal-footer)], render_list => [qw(key_actions)],);

1;
