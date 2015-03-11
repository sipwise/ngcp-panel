package NGCP::Panel::Form::EmailTemplate::Admin;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::EmailTemplate::Reseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name from_email subject body/],
);

1;

# vim: set tabstop=4 expandtab:
