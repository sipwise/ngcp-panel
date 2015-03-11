package NGCP::Panel::Field::SubscriberPbxGroup;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

# agranig: this is just a dummy for the API, do not use in panel!

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'PBX Group',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/subscriber/pbx_group_ajax',
    table_titles => ['#', 'Name', 'Contract #', 'Status'],
    table_fields => ['id', 'name', 'contract_id', 'status'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create PBX Group',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;
