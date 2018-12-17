package NGCP::Panel::Form::Header::ResellerRuleSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::ResellerRuleSet';

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name description/],
);

1;

# vim: set tabstop=4 expandtab:
