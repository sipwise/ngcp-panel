package NGCP::Panel::Form::Peering::ServerAPI;
use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Peering::Server';

has_field 'group_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The peering group this server belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/group_id name ip host port transport weight via_route probe enabled/],
);

1;
__END__

=head1 NAME

NGCP::Panel::Form::Peering::ServerAPI

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
