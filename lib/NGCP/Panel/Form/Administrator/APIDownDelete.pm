package NGCP::Panel::Form::Administrator::APIDownDelete;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'ca' => (
    type => 'Compound',
    label => 'Download CA Certificate',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw(row)],
);

has_field 'ca.download' => (
    type => 'Submit',
    value => 'Download CA Cert',
    element_class => [qw(btn btn-tertiary)],
    do_wrapper => 0,
    do_label => 0,
);

has_field 'ca.description' => (
    type => 'Display',
    html => '<div class="ngcp-form-desc">The Server Certificate. Needed if you want to verify the server connection in your API client, and the server certificate is not signed by a well-known CA or is self-signed.</div>',
    do_wrapper => 0,
    do_label => 0,
);


has_field 'del' => (
    type => 'Compound',
    label => 'Delete Key',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw(row)],
);

has_field 'del.delete' => (
    type => 'Submit',
    value => 'Delete',
    element_class => [qw(btn btn-secondary)],
    do_wrapper => 0,
    do_label => 0,
);

has_field 'del.description' => (
    type => 'Display',
    html => '<div class="ngcp-form-desc">Remove Certificate and revoke API Access for this user.</div>',
    do_wrapper => 0,
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(ca del)],
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
