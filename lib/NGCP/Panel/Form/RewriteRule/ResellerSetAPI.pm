package NGCP::Panel::Form::RewriteRule::ResellerSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::RewriteRule::ResellerSet';

has_field 'rewriterules' => (
    type => 'Repeatable',
    required => 0,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Rewrite Rules'],
    },
);
has_field 'rewriterules.contains' => ( type => '+NGCP::Panel::Field::RewriteRuleAPI' );

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name description rewriterules/],
);


1;

# vim: set tabstop=4 expandtab:
