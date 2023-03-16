package NGCP::Panel::Field::ParentSoundSet;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Parent',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/sound_parent/ajax',
    table_titles => ['#', 'Name', 'Description', 'Parent'],
    table_fields => ['id', 'name', 'description', 'parent.name'],
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
