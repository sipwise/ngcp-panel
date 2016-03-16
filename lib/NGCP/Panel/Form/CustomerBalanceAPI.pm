package NGCP::Panel::Form::CustomerBalanceAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::CustomerBalance';
use Moose::Util::TypeConstraints;

has_field 'cash_balance_interval' => (
    type => 'Money',
    label => 'Cash Balance (Interval)',
    required => 1,
    inflate_method => sub { return $_[1] * 100 },
    deflate_method => sub { return $_[1] / 100 },
    element_attr => {
        rel => ['tooltip'],
        title => ['The current cash balance of the customer in EUR/USD/etc for the current interval.'],
    },
);

has_field 'free_time_balance_interval' => (
    type => 'Integer',
    label => 'Free-Time Balance',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The current free-time balance of the customer for the current interval in seconds.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/cash_balance cash_balance_interval free_time_balance free_time_balance_interval/],
);

1;

=head1 NAME

NGCP::Panel::Form::CustomerBalanceAPI

=head1 DESCRIPTION



=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
