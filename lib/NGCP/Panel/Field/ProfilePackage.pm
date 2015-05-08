package NGCP::Panel::Field::ProfilePackage;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Package',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/package/ajax',
    table_titles => ['#', 'Reseller', 'Package'],
    table_fields => ['id', 'reseller_name', 'name'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Profile Package',
    element_class => [qw/btn btn-tertiary pull-right/],
    #element_attr => { onclick => 'this.form.submit();return false;' }, #without this, only the first create button works
);

1;

# vim: set tabstop=4 expandtab:
