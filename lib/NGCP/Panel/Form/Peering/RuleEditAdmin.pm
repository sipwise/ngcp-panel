package NGCP::Panel::Form::Peering::RuleEditAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Peering::Rule';

has_field 'group' => (
    type => '+NGCP::Panel::Field::PeeringGroupSelect',
    label => 'Peering Group',
    not_nullable => 1,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A peering group the rule belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/callee_prefix callee_pattern caller_pattern description enabled stopper group/],
);

1;
__END__

=head1 NAME

NGCP::Panel::Form::Peering::RuleEdit

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
