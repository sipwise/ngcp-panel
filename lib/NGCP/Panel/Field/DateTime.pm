package NGCP::Panel::Field::DateTime;
use HTML::FormHandler::Moose;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime qw//;
extends 'HTML::FormHandler::Field::Text';

has '+deflate_method' => ( default => sub { \&datetime_deflate } );
has '+inflate_method' => ( default => sub { \&datetime_inflate } );

sub datetime_deflate {  # deflate: DateTime (in any tz) -> User representation (with correct tz)
    my ( $self, $value ) = @_;

    my $c = $self->form->ctx;

    if(blessed($value) && $value->isa('DateTime')) {
        if($c && $c->session->{user_tz}) {
            $value->set_time_zone('local');                 # starting point for conversion
            $value->set_time_zone($c->session->{user_tz});  # desired time zone
        }
        return $value->ymd('-') . ' ' . $value->hms(':');
    } else {
        return $value;
    }
}

sub datetime_inflate {  # inflate: User entry -> DateTime -> Plaintext but converted
    my ( $self, $value ) = @_;

    my $c = $self->form->ctx;

    my $tz;
    if($c && $c->session->{user_tz}) {
        $tz = $c->session->{user_tz};
    }

    my $date = NGCP::Panel::Utils::DateTime::from_forminput_string($value, $tz);
    unless ($date) {
        $self->add_error('Could not parse DateTime input. Should be one of (Y-m-d H:M:S, Y-m-d H:M, Y-m-d).');
        return;
    }
    $date->set_time_zone('local');  # convert to local

    return $date->ymd('-') . ' ' . $date->hms(':');
}

no Moose;
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
