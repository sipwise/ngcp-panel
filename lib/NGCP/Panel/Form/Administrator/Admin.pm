package NGCP::Panel::Form::Administrator::Admin;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'NGCP::Panel::Form::Administrator::Reseller';

has_field 'is_superuser' => (type => 'Boolean');
has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    validate_when_empty => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        reseller login auth_mode password email role_id is_master is_active read_only enable_2fa show_passwords call_data billing_data can_reset_password
    )],
);

1;
