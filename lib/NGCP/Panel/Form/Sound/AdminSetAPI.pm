package NGCP::Panel::Form::Sound::AdminSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Sound::ResellerSetAPI';

has_field 'reseller_id' => (
    type => 'PosInteger',
    label => 'Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller this sound set belongs to.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller_id customer_id name description expose_to_customer contract_default parent_id parent_name copy_from_default language loopplay replace_existing/],
);


1;

=head1 NAME

NGCP::Panel::Form::SoundSet

=head1 DESCRIPTION

Form to modify a provisioning.voip_sound_sets row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
