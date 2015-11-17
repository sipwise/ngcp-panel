package NGCP::Panel::Field::Regexp;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Text';

sub validate {
    my ( $self ) = @_;
    my $pattern = $self->value;
    my $valid_regexp = eval {
        qr/$pattern/;
    } or return $self->add_error($self->label . " is no valid regexp");
    return 1;
}

1;

=head1 NAME

NGCP::Panel::Field::Regexp

=head1 DESCRIPTION

This accepts a regexp that can be validated in perl. It subclasses
L<HTML::FormHandler::Field::Text>.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
