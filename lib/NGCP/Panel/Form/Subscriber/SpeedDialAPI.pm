package NGCP::Panel::Form::Subscriber::SpeedDialAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'speeddials' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of hashes, each containing the keys "slot" ("*0 .. *9") and "destination" (A valid SIP URI).'],
    },
);

has_field 'speeddials.slot' => (
    type => 'Text',
    label => 'Slot',
    required => 1,
);

has_field 'speeddials.destination' => (
    type => 'Text',
    label => 'Destination',
    required => 1,
);

sub validate_speeddials_slot {
    my ($self, $field) = @_;

    return unless $self->ctx;
    my $slots = $self->ctx->config->{speed_dial_vsc_presets}->{vsc};
    return unless $slots;
    unless(grep {$_ eq $field->value} @{ $slots }) {
        my $err_msg = 'Slot invalid.';
        $field->add_error($err_msg);
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
