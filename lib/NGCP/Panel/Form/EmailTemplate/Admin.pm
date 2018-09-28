package NGCP::Panel::Form::EmailTemplate::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::EmailTemplate::Reseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 0,
    required => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name from_email subject body attachment_name/],
);

1;

# vim: set tabstop=4 expandtab:
