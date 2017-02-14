package NGCP::Panel::Form::Balance::CustomerBalanceAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Balance::CustomerBalance';
use Moose::Util::TypeConstraints;

has_field 'cash_debit' => (
    type => 'Money',
    #label => 'Cash Balance (Interval)',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The amount spent during the current interval in EUR/USD/etc (read-only).'],
    },
);

has_field 'free_time_spent' => (
    type => 'Integer',
    #label => 'Free-Time Balance',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The free-time spent during the current interval in seconds (read-only).'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/cash_balance cash_debit free_time_balance free_time_spent/],
);

1;

=head1 NAME

NGCP::Panel::Form::Balance::CustomerBalanceAPI

=head1 DESCRIPTION



=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
