package NGCP::Panel::Form::Customer::PbxExtensionSubscriberEdit;

use HTML::FormHandler::Moose;

extends 'NGCP::Panel::Form::Customer::PbxExtensionSubscriber';

#This separate package exists to avoid collisions between cached edit form with one that is used for subscriber creation

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/domain group_select alias_select pbx_extension display_name email webusername webpassword password administrative lock status external_id timezone profile_set profile/ ],
);

1;

=head1 NAME

NGCP::Panel::Form::PbxExtensionSubscriberEdit

=head1 DESCRIPTION

Form to modify a subscriber.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
