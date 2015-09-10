package NGCP::Panel::Form::MaliciousCall::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::MaliciousCall::Reseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller call_id caller callee start_time duration caller_id callee_id reported_at/],
);

1;

# vim: set tabstop=4 expandtab:
