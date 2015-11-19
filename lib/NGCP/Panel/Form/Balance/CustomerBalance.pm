package NGCP::Panel::Form::Balance::CustomerBalance;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
#use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'cash_balance' => (
    type => 'Money',
    label => 'Cash Balance',
    required => 1,
    inflate_method => sub { return $_[1] * 100.0 },
    deflate_method => sub { return $_[1] / 100.0 },
    element_attr => {
        rel => ['tooltip'],
        title => ['The current cash balance of the customer in EUR/USD/etc.']
    },
);

has_field 'free_time_balance' => (
    type => 'Integer',
    label => 'Free-Time Balance',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The current free-time balance of the customer in seconds.']
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/cash_balance free_time_balance/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::Balance::CustomerBalance

=head1 DESCRIPTION



=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
