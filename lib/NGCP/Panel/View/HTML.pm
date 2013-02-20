package NGCP::Panel::View::HTML;
use Moose;
use namespace::autoclean;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,

    WRAPPER => 'wrapper.tt'
);

=head1 NAME

NGCP::Panel::View::HTML - TT View for NGCP::Panel

=head1 DESCRIPTION

TT View for NGCP::Panel.

=head1 SEE ALSO

L<NGCP::Panel>

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

# vim: set tabstop=4 expandtab:
