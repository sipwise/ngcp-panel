package NGCP::Panel::Form::Domain::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Domain::Reseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id reseller domain/],
);

1;
# vim: set tabstop=4 expandtab:
