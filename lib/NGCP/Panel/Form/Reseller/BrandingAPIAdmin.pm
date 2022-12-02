package NGCP::Panel::Form::Reseller::BrandingAPIAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Reseller::BrandingAPI';

has_field 'reseller_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller who owns the Branding.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller_id logo css csc_color_primary csc_color_secondary/],
);

sub update_fields {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);
    $self->field('logo')->inactive(1);
}

1;
# vim: set tabstop=4 expandtab:
