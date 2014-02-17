package NGCP::Panel::View::SVG;

use Sipwise::Base;
use NGCP::Panel::Utils::I18N;

use strict;
extends 'Catalyst::View::TT';


__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
    ENCODING => 'UTF-8',
    WRAPPER => '',
    FILTERS => {},
    ABSOLUTE => 0,
    expose_methods => [],
);

sub process
{
    my ( $self, $c ) = @_;
    $c->res->content_type("image/svg+xml");
    $self->SUPER::process($c);
    return 1;
}

1;