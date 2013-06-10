package NGCP::Panel::Field::EmailList;
use HTML::FormHandler::Moose;
use Email::Valid;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Text';

sub validate {
    my ( $self ) = @_;
    my @emails = $self->value->split(',');
    for my $mail (@emails) {
        unless( Email::Valid->address(
            -address  => $mail,
            -tldcheck => 0,
            -mxcheck  => 0,
            -allow_ip => 1,
            -fudge    => 0,
        ) ) {
            return $self->add_error($mail . " is no valid email address");
        }
    }
    return 1;
}

1;

=head1 NAME

NGCP::Panel::Field::EmailList

=head1 DESCRIPTION

This accepts a comma (,) separated list of email addresses using
L<Email::Valid>. It does not check for a valid TLD allows IP addresses for
the domain part. It subclasses L<HTML::FormHandler::Field::Text>.

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
