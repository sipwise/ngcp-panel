package NGCP::Panel::Form::CustomerFraudEvents::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::CustomerFraudEvents::Reseller';
#use Moose::Util::TypeConstraints;

has_field 'reseller_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this customer belongs to.']
    },
);

1;

=head1 NAME

NGCP::Panel::Form::CustomerFraudEvents::Admin

=head1 DESCRIPTION

=head1 METHODS

=head1 AUTHOR

Kirill Solomko

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
