package NGCP::Panel::View::HTML;
use Sipwise::Base;

use URI::Escape qw/uri_unescape/;

extends 'Catalyst::View::TT';

use NGCP::Panel::Utils::I18N;

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
    ENCODING => 'UTF-8',
    WRAPPER => 'wrapper.tt',
    FILTERS => {
        uri_unescape => sub {
            URI::Escape::uri_unescape(@_);
        },
    },
    expose_methods => [qw/translate_form/],
);

sub translate_form {
    my $self = shift;
    NGCP::Panel::Utils::I18N->translate_form(@_);
}

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
