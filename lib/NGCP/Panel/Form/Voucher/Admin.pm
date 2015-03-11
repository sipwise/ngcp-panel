package NGCP::Panel::Form::Voucher::Admin;

use HTML::FormHandler::Moose;
use parent 'NGCP::Panel::Form::Voucher::Reseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this voucher belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller code amount valid_until customer/],
);


1;
# vim: set tabstop=4 expandtab:
