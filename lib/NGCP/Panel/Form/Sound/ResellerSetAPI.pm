package NGCP::Panel::Form::Sound::ResellerSetAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Sound::SubadminSetAPI';

has_field 'contract_id' => (
    type => 'PosInteger',
    label => 'Customer',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract used for this subscriber.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/customer_id name description contract_default copy_from_default language loopplay override/],
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
