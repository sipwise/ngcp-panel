package NGCP::Panel::Field::Regexp;
use HTML::FormHandler::Moose;
use Regexp::Parser;
extends 'HTML::FormHandler::Field::Text';

my $parser = Regexp::Parser->new();

sub validate {
    my ( $self ) = @_;
    my $pattern = $self->value;
    return $self->add_error($self->label . " is no valid regexp")
        unless $parser->regex($pattern);
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
