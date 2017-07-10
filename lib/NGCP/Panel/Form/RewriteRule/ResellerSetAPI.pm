package NGCP::Panel::Form::RewriteRule::ResellerSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::RewriteRule::ResellerSet';

has_field 'rewriterules' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the Rewrite Rule Set.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name description/],
);


1;

# vim: set tabstop=4 expandtab:
