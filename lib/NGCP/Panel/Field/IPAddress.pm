package NGCP::Panel::Field::IPAddress;
use HTML::FormHandler::Moose;
use Data::Validate::IP qw(is_ipv4 is_ipv6);
use parent 'HTML::FormHandler::Field::Text';

sub validate {
    my ( $self ) = @_;
    return $self->add_error($self->label . " is no valid IPv4 or IPv6 address.")
        unless( is_ipv4($self->value) or is_ipv6($self->value) );
    return 1;
}

1;

=head1 NAME

NGCP::Panel::Field::IPAddress

=head1 DESCRIPTION

This accepts a valid IPv4 or IPv6 address (without square brackets).
For details on the validation see L<Data::Validate::IP>.
It subclasses L<HTML::FormHandler::Field::Text>.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
