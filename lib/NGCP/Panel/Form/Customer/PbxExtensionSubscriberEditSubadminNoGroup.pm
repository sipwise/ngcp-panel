package NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadminNoGroup;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/alias_select email webusername webpassword password profile/ ],
);

sub update_fields {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    my $profile_set = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_subscriber_profile_set;
    if($profile_set) {
        $self->field('profile')->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/profile_ajax', [$profile_set->id])->as_string
        );
    }

    if($c->user->roles eq "subscriberadmin") {
        if(!$c->config->{security}->{password_sip_expose_subadmin}) {
            $self->field('password')->inactive(1);
        }
        if(!$c->config->{security}->{password_web_expose_subadmin}) {
            $self->field('webpassword')->inactive(1);
        }
    }

    $self->field('password')->required(0); # optional on edit
}

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
