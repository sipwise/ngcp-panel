package NGCP::Panel::Form::Customer::PbxExtensionSubscriber;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';

has_field 'group' => (
    type => '+NGCP::Panel::Field::PbxGroup',
    label => 'Group',
    validate_when_empty => 1,
);

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
    render_list => [qw/group pbx_extension display_name webusername webpassword username password status external_id profile/ ],
);

sub field_list {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    print "+++++++++++++++++++++++++++++ PbxExtensionSubscribert field_list\n";

    my $group = $self->field('group');
    $group->field('id')->ajax_src(
        $c->uri_for_action('/customer/pbx_group_ajax', [$c->stash->{customer_id}])->as_string
    );

    if($c->stash->{admin_subscriber}) {
        my $profile_set = $c->stash->{admin_subscriber}->provisioning_voip_subscriber->voip_subscriber_profile_set;
        if($profile_set && $self->field('profile')) {
            $self->field('profile')->field('id')->ajax_src(
                $c->uri_for_action('/subscriberprofile/profile_ajax', [$profile_set->id])->as_string
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
