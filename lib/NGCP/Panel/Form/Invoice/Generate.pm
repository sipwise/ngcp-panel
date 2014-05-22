package NGCP::Panel::Form::Invoice::Generate;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ValidatorBase';

use DateTime;
use DateTime::Format::Strptime;
use NGCP::Panel::Utils::DateTime;

has_field 'submitid' => ( type => 'Hidden' );
has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'client_contract_id' => (
    is => 'rw',
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contract',
    #name => 'client_contract_id',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    #we will set it in controller 
    #ajax_src => $c->uri_for_action( '/invoice/ajax_datatables_data', [ $self->provider_id, 'invoice_list_data' ],
    ajax_src => '',
    table_titles => ['Contract Id',  'First Name', 'Last Name', 'Email'],
    table_fields => ['contracts.id', 'firstname', 'lastname',   'email'],
);

has_field 'start' => ( 
    type => '+NGCP::Panel::Field::DatePicker',
    label => 'Start Date',
    default => NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month')->ymd,
    required => 1,
);

has_field 'end' => ( 
    type => '+NGCP::Panel::Field::DatePicker',
    label => 'End Date',
    default => NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month')->add( months => 1)->subtract(seconds=>1)->ymd,
    required => 1,
);

has_field 'save' => (
    type => 'Button',
    value => 'Generate',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

#has_field 'client_contract_id_hidden' => (
#    type => 'Hidden',
#    required => 1,
#);

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
        #pattern => '%Y-%m-%d %H:%M:%S',
        pattern => '%Y-%m-%d',
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
