package NGCP::Panel::Form::Reseller::BrandingAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Reseller::Branding';

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/logo css csc_color_primary csc_color_secondary/],
);

sub update_fields {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);
    $self->field('logo')->inactive(1);
}

1;
# vim: set tabstop=4 expandtab:
