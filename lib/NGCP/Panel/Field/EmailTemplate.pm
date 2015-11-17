package NGCP::Panel::Field::EmailTemplate;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    #label => 'Email Template',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/emailtemplate/ajax',
    table_titles => ['#', 'Reseller', 'Name', 'Subject'],
    table_fields => ['id', 'reseller_name', 'name', 'subject'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Email Template',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;
