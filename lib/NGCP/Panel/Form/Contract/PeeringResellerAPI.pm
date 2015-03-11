package NGCP::Panel::Form::Contract::PeeringResellerAPI;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::Contract::PeeringReseller';

has_field 'type' => (
    type => 'Select',
    options => [
        { value => 'sippeering', label => 'Peering'},
        { value => 'reseller', label => 'Reseller'},
    ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either "sippeering" or "reseller".']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile status external_id type/],
);

1;
# vim: set tabstop=4 expandtab:
