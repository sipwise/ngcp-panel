package NGCP::Panel::Form::Invoice::Send;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ValidatorBase';

has_field 'submitid' => ( type => 'Hidden' );
has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'email' => ( 
    type => 'Text',
    label => 'Emails',
    required => 1,
);

has_field 'save' => (
    type => 'Button',
    value => 'Send',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/email/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::InvoiceTemplate

=head1 DESCRIPTION

Form to modify an invoice template.

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
