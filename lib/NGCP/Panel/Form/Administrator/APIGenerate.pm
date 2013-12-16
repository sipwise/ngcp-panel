package NGCP::Panel::Form::Administrator::APIGenerate;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'gen' => (
    type => 'Compound',
    label => 'Generate Certificate',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw(row)],
);

has_field 'gen.generate' => (
    type => 'Submit',
    value => 'Generate',
    element_class => [qw(btn btn-primary)],
    do_wrapper => 0,
    do_label => 0,
);

has_field 'gen.description' => (
    type => 'Display',
    html => '<div class="ngcp-form-desc">Generates an X.509 Client Certificate for API Clients (PEM Format) and for Browser Import (PKCS12 Format).</div>',
    do_wrapper => 0,
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(gen)],
);

has_field 'close' => (
    type => 'Submit',
    do_label => 0,
    value => 'Close',
    element_class => [qw(btn btn-tertiary)],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw(modal-footer)],
    render_list => [qw(close)],
);

1;

# vim: set tabstop=4 expandtab:
