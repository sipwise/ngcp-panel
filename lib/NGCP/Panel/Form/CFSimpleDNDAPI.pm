package NGCP::Panel::Form::CFSimpleDNDAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber ID.'],
    },
);

has_field 'secretary_numbers' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
);

has_field 'secretary_numbers.number' => (
    type => 'Text',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(subscriber_id secretary_numbers)],
);

1;

# vim: set tabstop=4 expandtab:
