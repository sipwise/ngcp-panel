package NGCP::Panel::Form::Rtc::AppsAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Rtc::AppsReseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    #validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this app belong to.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller rtc_user_id apps/],
);

1;
# vim: set tabstop=4 expandtab:
