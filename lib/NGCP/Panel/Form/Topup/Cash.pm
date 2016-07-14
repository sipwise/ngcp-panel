package NGCP::Panel::Form::Topup::Cash;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'amount' => (
    type => 'Money',
    label => 'Amount',
    required => 1,
    inflate_method => sub { return $_[1] * 100.0 },
    deflate_method => sub { return $_[1] / 100.0 },
    element_attr => {
        rel => ['tooltip'],
        title => ['The amount to top up in Euro/USD/etc.']
    },
);

has_field 'package' => (
    type => '+NGCP::Panel::Field::ProfilePackage',
    #validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile package the customer will switch to.']
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Perform top-up',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/amount package/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::Topup::Cash

=head1 DESCRIPTION



=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
