package NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditAdmin;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxExtensionSubscriberEdit';

with 'NGCP::Panel::Render::RepeatableJs';

has_field 'alias_number' => (
    type => '+NGCP::Panel::Field::AliasNumber',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'alias_number_add' => (
    type => 'AddElement',
    repeatable => 'alias_number',
    value => 'Add another number',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/group pbx_extension alias_number alias_number_add email webusername webpassword password status external_id profile_set profile/ ],
);

sub field_list {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);

    print "+++++++++++++++++++++++++++++ PbxExtensionSubscriberEditAdmin field_list\n";

    my $profile_set = $self->field('profile_set');
    if($profile_set) {
        $profile_set->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/set_ajax_reseller', [$c->stash->{subscriber}->contract->contact->reseller_id])->as_string
        );
    }

    my $set_id = $c->stash->{subscriber}->provisioning_voip_subscriber->profile_set_id;
    if($set_id) {
        my $profile = $self->field('profile');
        if($profile) {
            $profile->field('id')->ajax_src(
                $c->uri_for_action('/subscriberprofile/profile_ajax', [$set_id])->as_string
            );
        }
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
