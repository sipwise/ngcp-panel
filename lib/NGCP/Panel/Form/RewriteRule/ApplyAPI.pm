package NGCP::Panel::Form::RewriteRule::ApplyAPI;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'Subscriber #',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ID of the subscriber to apply rules for']
    },
);

has_field 'number' => (
    type => 'Text',
    label => 'User or number to rewrite',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The username or number to rewrite']
    },
);

has_field 'direction' => (
    type => 'Select',
    label => 'Direction',
    required => 1,
    options => [
        { label => 'caller_in', value => 'caller_in' },
        { label => 'callee_in', value => 'callee_in' },
        { label => 'caller_out', value => 'caller_out' },
        { label => 'callee_out', value => 'callee_out' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The direction rule set to apply, one of caller_in, callee_in, caller_out, callee_out']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/subscriber_id number direction/],
);

1;

# vim: set tabstop=4 expandtab:
