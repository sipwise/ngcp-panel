package NGCP::Panel::Form::MaliciousCall::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
);

has_field 'callee_uuid' => (
    type => 'Hidden',
);

has_field 'call_id' => (
    type => 'Text',
    label => 'Call-Id',
    required => 1,
);

has_field 'caller' => (
    type => 'Text',
    label => 'Caller',
    required => 1,
);

has_field 'callee' => (
    type => 'Text',
    label => 'Callee',
    required => 1,
);

has_field 'start_time' => (
    type => 'Text',
    label => 'Called at',
    required => 1,
);

has_field 'duration' => (
    type => 'PosInteger',
    label => 'Duration',
    required => 1,
);

has_field 'source' => (
    type => 'Text',
    label => 'Source',
    required => 1,
);

has_field 'reported_at' => (
    type => 'Text',
    label => 'Reported at',
    required => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id callee_uuid call_id caller callee start_time duration source reported_at/],
);

1;

# vim: set tabstop=4 expandtab:
