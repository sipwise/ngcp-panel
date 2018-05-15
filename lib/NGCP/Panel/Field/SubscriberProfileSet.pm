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

no Moose;

1;

__END__

=head1 NAME

NGCP::Panel::Field::SubscriberProfileSet

=head1 DESCRIPTION

A helper to manipulate the subscriber profile set data

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
