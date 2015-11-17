package NGCP::Panel::Field::SubscriberProfile;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Profile',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    table_titles => ['#', 'Profile Set', 'Name', 'Description'],
    table_fields => ['id', 'profile_set_name', 'name', 'description'],
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
