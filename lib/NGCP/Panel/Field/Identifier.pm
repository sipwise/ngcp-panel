package NGCP::Panel::Field::Identifier;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Text';

sub validate {
    my ( $self ) = @_;
    return $self->add_error("Cannot contain spaces.")
        if ( $self->value =~ m/ / );
    return $self->add_error("Invalid identifier (dots not allowed at this position).")
        if ( $self->value =~ m/^\./ or
             $self->value =~ m/\.$/ or
             $self->value =~ m/\.\./ );
    return $self->add_error("Contains invalid symbols.")
        unless ( $self->value =~ m/^[[:lower:][:upper:][:digit:]=+,;_.~'()-]+$/ );
    return 0;
}

1;

=head1 NAME

NGCP::Panel::Field::Identifier

=head1 DESCRIPTION

This accepts a value which contains any number of alphanumeric characters.
Its main use is for SIP usernames of subscribers.

Alphanumeric lowercase characters plus the following symbols
are allowed: C<=+,;_.~'()-> Spaces are not allowed. Dots can not stand at
the beginning or end of the identifier and two or more dots can not be in
a row.

This definition has been taken from L<Sipwise::Provisioning::check_localpart>.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
