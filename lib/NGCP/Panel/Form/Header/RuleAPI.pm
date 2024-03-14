package NGCP::Panel::Form::Header::RuleAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::Rule';

has_field 'set_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Header rule set id, one the rule must belong to.'],
        expand => {
            class => 'NGCP::Panel::Role::API::HeaderRuleSets',
            allowed_roles => [qw(admin reseller)],
        },
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Subscriber id, to create a subscriber assigned header rule.'],
    },
);

has_field 'conditions' => (
    type => 'Compound',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The list of conditions in the rule.'],
    },
);

has_field 'actions' => (
    type => 'Compound',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The list of actions in the rule.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name direction description stopper enabled set_id priority/],
);

1;

# vim: set tabstop=4 expandtab:
