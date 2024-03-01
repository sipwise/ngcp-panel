package NGCP::Panel::Form::Subscriber::LocationEntryAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber::LocationEntry';

has '+use_fields_for_input_without_param' => ( default => 1 );

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber the contact belongs to.']
    },
);

has_field 'expires' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The expire timestamp of the registered contact.']
    },
);

has_field 'nat' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The registered contact is detected as behind NAT.']
    },
);

has_field 'received' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Source IP and Port of subscriber registration.']
    },
);

has_field 'socket' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Points to the LB interface from which the incoming calls to this registration should be sent out.']
    },
);

1;

__END__

=head1 NAME

NGCP::Panel::Form::Subscriber::RegisteredAPI

=head1 DESCRIPTION

A helper to manipulate the registered API subscriber form

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
