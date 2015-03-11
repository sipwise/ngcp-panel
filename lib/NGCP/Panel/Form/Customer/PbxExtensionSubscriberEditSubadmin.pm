package NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
use parent 'NGCP::Panel::Form::Customer::PbxExtensionSubscriber';

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/group_select pbx_extension email webusername webpassword password alias_select profile/ ],
);

override 'update_fields' => sub {
    my $self = shift;
    my $c = $self->ctx;

    super();

    if($c->user->roles eq "subscriberadmin") {
        if(!$c->config->{security}->{password_sip_expose_subadmin}) {
            $self->field('password')->inactive(1);
        }
        if(!$c->config->{security}->{password_web_expose_subadmin}) {
            $self->field('webpassword')->inactive(1);
        }
    }
};

1;

=head1 NAME

NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin

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
