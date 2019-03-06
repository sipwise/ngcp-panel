package NGCP::Panel::Form::Header::ResellerRuleSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::ResellerRuleSet';

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'Ruleset owner',
    required => 0,
    fif_from_value => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/subscriber_id name description/],
);

1;

# vim: set tabstop=4 expandtab:
