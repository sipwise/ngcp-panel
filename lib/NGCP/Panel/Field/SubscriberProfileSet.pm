package NGCP::Panel::Field::SubscriberProfileSet;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Profile Set',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/subscriberprofile/ajax',
    table_titles => ['#', 'Reseller', 'Name', 'Description'],
    table_fields => ['id', 'reseller_name', 'name', 'description'],
);

=pod
has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Profile Set',
    element_class => [qw/btn btn-tertiary pull-right/],
);
=cut

1;
