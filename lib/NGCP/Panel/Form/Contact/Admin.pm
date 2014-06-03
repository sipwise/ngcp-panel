package NGCP::Panel::Form::Contact::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contact::Reseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this contact belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller firstname lastname email company street postcode city
        country iban bic vatnum comregnum phonenumber mobilenumber faxnumber/],
);

1;
# vim: set tabstop=4 expandtab:
