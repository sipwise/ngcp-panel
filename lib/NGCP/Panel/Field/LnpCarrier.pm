package NGCP::Panel::Field::LnpCarrier;
use Moose;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'LNP Carrier',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/lnp/carrier_ajax',
    table_titles => ['#', 'Name', 'Prefix'],
    table_fields => ['id', 'name', 'prefix'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create LNP Carrier',
    element_class => [qw/btn btn-tertiary pull-right/],
);

sub validate {
    my ( $self ) = @_;
    my $value = $self->value;
    $self->add_error('LNP carrier id must be a positive integer')
        if(!$self->has_errors && $value->{id} !~ /^\d+$/);
}

no Moose;
1;
