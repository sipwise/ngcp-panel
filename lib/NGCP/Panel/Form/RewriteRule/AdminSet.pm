package NGCP::Panel::Form::RewriteRule::AdminSet;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::RewriteRule::ResellerSet';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller who can use the Ruleset.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name description/],
);

1;

# vim: set tabstop=4 expandtab:
