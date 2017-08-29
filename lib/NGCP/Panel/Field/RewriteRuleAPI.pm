package NGCP::Panel::Field::RewriteRuleAPI;
use Moose;
use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Field::RewriteRule';

has_field 'priority' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The rewrite rule priority.']
    },
);

1;

# vim: set tabstop=4 expandtab:
