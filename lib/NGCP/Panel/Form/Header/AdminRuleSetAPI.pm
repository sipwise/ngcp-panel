package NGCP::Panel::Form::Header::AdminRuleSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::ResellerRuleSet';

has_field 'reseller_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller who can use the Ruleset.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller_id name description/],
);

1;

# vim: set tabstop=4 expandtab:
