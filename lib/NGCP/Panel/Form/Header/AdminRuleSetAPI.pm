package NGCP::Panel::Form::Header::AdminRuleSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::ResellerRuleSetAPI';

has_field 'reseller_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller who can use the Ruleset.'],
    },
);

has_field 'rules' => (
    type => '+NGCP::Panel::Field::HeaderRule',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The list of rules in the set.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller_id subscriber_id name description rules/],
);

1;

# vim: set tabstop=4 expandtab:
