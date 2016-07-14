package NGCP::Panel::Form::CustomerFraudEvents::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::CustomerFraudEvents::Reseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 0,
    required => 0,
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
