package NGCP::Panel::Field::SubscriberProfile;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

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

no Moose;

1;

__END__

=head1 NAME

NGCP::Panel::Field::SubscriberProfile

=head1 DESCRIPTION

A helper to manipulate the subscriber profile fields

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
