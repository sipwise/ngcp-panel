package NGCP::Panel::Field::EmergencyMappingContainer;
use Moose;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Emergency Mapping Container',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/emergencymapping/emergency_container_ajax',
    table_titles => ['#', 'Reseller', 'Name'],
    table_fields => ['id', 'reseller.name', 'name'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Emergency Mapping Container',
    element_class => [qw/btn btn-tertiary pull-right/],
);

sub validate {
    my ( $self ) = @_;
    my $value = $self->value;
    $self->add_error('Emergency mapping container id must be a positive integer')
        if(!$self->has_errors && $value->{id} !~ /^\d+$/);
}

1;
