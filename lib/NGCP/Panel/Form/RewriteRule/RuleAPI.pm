package NGCP::Panel::Form::RewriteRule::RuleAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::RewriteRule::Rule';

has_field 'set_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The rewrite rule set this rule belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/set_id match_pattern replace_pattern description direction enabled field/],
);

1;
__END__

=head1 NAME

NGCP::Panel::Form::Peering::RuleAPI

=head1 DESCRIPTION

-

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
