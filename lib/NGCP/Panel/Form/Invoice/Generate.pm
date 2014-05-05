package NGCP::Panel::Form::Invoice::Generate;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ValidatorBase';
extends 'HTML::FormHandler::Field::Compound';

use Moose::Util::TypeConstraints;
use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+use_fields_for_input_without_param' => ( default => 1 );
sub build_render_list {[qw/fields actions/]}
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
has_field 'start' => ( 
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['YYYY-MM-DD HH:mm:ss']
    },
    label => 'Start Date/Time',
    required => 1,
);

has_field 'end' => ( 
    type => '+NGCP::Panel::Field::DateTime',
    element_attr => {
        rel => ['tooltip'],
        title => ['YYYY-MM-DD HH:mm:ss']
    },
    label => 'End Date/Time',
    required => 1,
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
