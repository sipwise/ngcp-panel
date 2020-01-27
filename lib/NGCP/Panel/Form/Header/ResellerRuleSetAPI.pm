package NGCP::Panel::Form::Header::ResellerRuleSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::ResellerRuleSet';

use NGCP::Panel::Utils::Subscriber;

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'Ruleset owner',
    required => 0,
    fif_from_value => 1,
);

has_field 'rules' => (
    type => 'Compound',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The list of rules in the set.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/subscriber_id name description rules/],
);

1;

# vim: set tabstop=4 expandtab:
