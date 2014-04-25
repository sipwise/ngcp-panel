package NGCP::Panel::View::TT;

use strict;
use base 'Catalyst::View::TT';

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
    ENCODING => 'UTF-8',
    FILTERS => {
        uri_unescape => sub {
            URI::Escape::uri_unescape(@_);
        },
    },
);

=head1 NAME

NGCP::Panel::View::TT - Catalyst plain TT View

=head1 SYNOPSIS

See L<NGCP::Panel>

=head1 DESCRIPTION

Catalyst JSON View.

=head1 AUTHOR

Gerhard,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
