package NGCP::Panel::Form::Contact::AdminAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contact::Reseller';

has_field 'reseller_id' => (
    type => 'PosInteger',
    required => 1,
    label => 'Contact reseller id',
    element_attr => {
        rel => ['tooltip'],
        title => ['Contact entry reseller id'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller_id firstname lastname email company street postcode city
        country iban bic bankname vatnum comregnum phonenumber mobilenumber faxnumber
        timezone
        gpp0 gpp1 gpp2 gpp3 gpp4 gpp5 gpp6 gpp7 gpp8 gpp9
        /],
);

1;
# vim: set tabstop=4 expandtab:
