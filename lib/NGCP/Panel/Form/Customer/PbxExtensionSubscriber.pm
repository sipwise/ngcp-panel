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

has_field 'alias_select' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Numbers',
    do_label => 0,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_multifield.tt',
    ajax_src => '/invalid',
    table_titles => ['#', 'Number', 'Subscriber'],
    table_fields => ['id', 'number', 'subscriber_username'],
);


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/group alias_select pbx_extension display_name email webusername webpassword username password status external_id profile_set profile/ ],
);

sub field_list {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    print ">>>>>>>>>>>>>> PbxExtensionSubscriber::field_list\n";

    if($self->field('alias_select') && $c->stash->{admin_subscriber}) {
        print ">>>>>>>>>>>>>>>> setting alias_select, url=" . $c->uri_for_action("/subscriber/aliases_ajax", [$c->stash->{admin_subscriber}->id]) . "\n";
        $self->field('alias_select')->ajax_src(
                $c->uri_for_action("/subscriber/aliases_ajax", [$c->stash->{admin_subscriber}->id])->as_string
            );
    }

    my $group = $self->field('group');
    $group->field('id')->ajax_src(
        $c->uri_for_action('/customer/pbx_group_ajax', [$c->stash->{customer_id}])->as_string
    );




    if($c->stash->{subscriber}) {

        my $profile_set_field = $self->field('profile_set');
        if($profile_set_field) {
            $profile_set_field->field('id')->ajax_src(
                $c->uri_for_action('/subscriberprofile/set_ajax_reseller', [$c->stash->{subscriber}->contract->contact->reseller_id])->as_string
            );
        }

        my $set_id = $c->stash->{subscriber}->provisioning_voip_subscriber->profile_set_id;
        if($set_id) {
            # don't show the profile set selection if we already have a profile set
            $profile_set_field->inactive(1) if($profile_set_field);

            my $profile = $self->field('profile');
            if($profile) {
                $profile->field('id')->ajax_src(
                    $c->uri_for_action('/subscriberprofile/profile_ajax', [$set_id])->as_string
                );
            }
        }
    } elsif($c->stash->{admin_subscriber}) {
        my $profile_set = $c->stash->{admin_subscriber}->provisioning_voip_subscriber->voip_subscriber_profile_set;
        if($profile_set && $self->field('profile')) {
            print ">>>>>>>>>>>>>> setting profile, url=" . $c->uri_for_action('/subscriberprofile/profile_ajax', [$profile_set->id]) . "\n";
            $self->field('profile')->field('id')->ajax_src(
                $c->uri_for_action('/subscriberprofile/profile_ajax', [$profile_set->id])->as_string
            );
        }
    }


    if($c->config->{security}->{password_sip_autogenerate}) {
        # todo: only set to inactive for certain roles, and only if specified in config
        $self->field('password')->inactive(1);
        $self->field('password')->required(0);
    }
    if($c->config->{security}->{password_web_autogenerate}) {
        # todo: only set to inactive for certain roles, and only if specified in config
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
