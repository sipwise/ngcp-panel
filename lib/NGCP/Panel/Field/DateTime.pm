package NGCP::Panel::Field::DateTime;
use HTML::FormHandler::Moose;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Text';

has '+deflate_method' => ( default => sub { \&datetime_deflate } );

sub datetime_deflate {
                my ( $self, $value ) = @_;             
                if(blessed($value) && $value->isa('DateTime')) {
                    return $value->ymd('-') . ' ' . $value->hms(':');;
                } else {
                    return $value;
                }
}

1;

=head1 NAME

NGCP::Panel::Field::DateTime

=head1 DESCRIPTION


=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
