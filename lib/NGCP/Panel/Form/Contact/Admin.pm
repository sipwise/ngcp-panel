package NGCP::Panel::Form::Contact::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contact::Reseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    not_nullable => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller firstname lastname email company
        street postcode city country phonenumber/],
);

1;
# vim: set tabstop=4 expandtab:
