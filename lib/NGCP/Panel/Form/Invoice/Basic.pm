package NGCP::Panel::Form::Invoice::Basic;

use Sipwise::Base;
use HTML::FormHandler::Moose;
#extends qw/HTML::FormHandler NGCP::Panel::Form::ValidatorBase/;
extends 'NGCP::Panel::Form::ValidatorBase';
use Moose::Util::TypeConstraints;

use DateTime;
use DateTime::Format::Strptime;

has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }


has_field 'submitid' => ( type => 'Hidden' );

#has_field 'contract.id' => (
#    type => '+NGCP::Panel::Field::DataTable',
#    label => 'Client',
#    do_label => 0,
#    do_wrapper => 0,
#    required => 1,
#    template => 'helpers/datatables_field.tt',
#    ajax_src => '/contact/ajax_noreseller',
#    table_titles => ['#', 'First Name', 'Last Name', 'Email'],
#    table_fields => ['id', 'firstname', 'lastname', 'email'],
#);
has_field 'invoice_id' => ( 
    type => 'Integer',
    required => 0,
);
has_field 'save' => (
    type => 'Button',
    value => 'Generate',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

has_field 'client_contract_id' => (
    type => 'Hidden',
    required => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/invoice_id client_contract_id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my $self = shift;
}

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
