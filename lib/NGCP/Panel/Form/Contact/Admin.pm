package NGCP::Panel::Form::Contact::Admin;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::Contact::Reseller';
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
        country iban bic bankname vatnum comregnum phonenumber mobilenumber faxnumber
        gpp0 gpp1 gpp2 gpp3 gpp4 gpp5 gpp6 gpp7 gpp8 gpp9
        /],
);

1;
# vim: set tabstop=4 expandtab:
