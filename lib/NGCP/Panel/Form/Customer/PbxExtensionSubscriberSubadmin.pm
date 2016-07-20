package NGCP::Panel::Form::Customer::PbxExtensionSubscriberSubadmin;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';

has_field 'pbx_extension' => (
    type => '+NGCP::Panel::Field::PosInteger',
    element_attr => { 
        rel => ['tooltip'], 
        title => ['Extension Number, e.g. 101'] 
    },
    required => 1,
    label => 'Extension',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/group_select alias_select pbx_extension display_name email webusername webpassword username password status profile/ ],
);

sub field_list {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    if($self->field('alias_select')) {
        my $sub;
        if($c->stash->{pilot}) {
            $sub = $c->stash->{pilot};
        } elsif($c->stash->{subscriber} && $c->stash->{subscriber}->provisioning_voip_subscriber->is_pbx_pilot) {
            $sub = $c->stash->{subscriber};
        }

        if($sub) {
            $self->field('alias_select')->ajax_src(
                    $c->uri_for_action("/subscriber/aliases_ajax", [$sub->id])->as_string
                );
        }
    }
    my $group = $self->field('group_select');
    if ($group) {
        $group->ajax_src(
            $c->uri_for_action('/customer/pbx_group_ajax', [$c->stash->{customer_id}])->as_string
        );
    }

    my $profile_set = $c->stash->{pilot}->provisioning_voip_subscriber->voip_subscriber_profile_set;
    if($profile_set) {
        $self->field('profile')->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/profile_ajax', [$profile_set->id])->as_string
        );
    }

    if($c->config->{security}->{password_sip_autogenerate}) {
        $self->field('password')->inactive(1);
        $self->field('password')->required(0);
    }
    if($c->config->{security}->{password_web_autogenerate}) {
        $self->field('webpassword')->inactive(1);
        $self->field('webpassword')->required(0);
    }
}


1;

=head1 NAME

NGCP::Panel::Form::Subscriber

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
