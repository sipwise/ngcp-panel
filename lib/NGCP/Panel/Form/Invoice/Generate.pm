package NGCP::Panel::Form::Invoice::Generate;

use Sipwise::Base;
use HTML::FormHandler::Moose;
#extends qw/HTML::FormHandler NGCP::Panel::Form::ValidatorBase/;
extends 'NGCP::Panel::Form::ValidatorBase';
use Moose::Util::TypeConstraints;

use DateTime;
use DateTime::Format::Strptime;

has '+widget_wrapper' => ( default => 'Bootstrap' );
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

has_field 'save' => (
    type => 'Button',
    value => 'Generate',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

has_field 'client_contract_id' => (
    type => 'Hidden',
    required => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/start end client_contract_id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my $self = shift;
    my $start = $self->field('start');
    my $end = $self->field('end');
    my $parser = DateTime::Format::Strptime->new(
        pattern => '%Y-%m-%d %H:%M:%S',
    );

    my $sdate = $parser->parse_datetime($start->value);
    unless($sdate) {
        $start->add_error("Invalid date format, must be YYYY-MM-DD hh:mm:ss");
    }
    my $edate = $parser->parse_datetime($end->value);
    unless($edate) {
        $end->add_error("Invalid date format, must be YYYY-MM-DD hh:mm:ss");
    }

    #unless(DateTime->compare($sdate, $edate) == -1) {
    #    my $err_msg = 'End time must be later than start time';
    #    $start->add_error($err_msg);
    #    $end->add_error($err_msg);
    #}
    #if(!$self->backend->checkSipPbxAccount()){
    #}
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
