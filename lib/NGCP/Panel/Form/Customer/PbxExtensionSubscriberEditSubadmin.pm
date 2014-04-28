package NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditSubadmin;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxExtensionSubscriberEdit';

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
    render_list => [qw/group pbx_extension email webusername webpassword password alias_select profile/ ],
);

sub update_fields {
    my $self = shift;
    my $c = $self->ctx;
    my $pkg = __PACKAGE__;
    $c->log->debug("my form: $pkg");

    $self->field('alias_select')->ajax_src(
            "".$c->uri_for_action("/subscriber/aliases_ajax", $c->req->captures)
        );

    my $group = $self->field('group');
    $group->field('id')->ajax_src(
        $c->uri_for_action('/customer/pbx_group_ajax', [$c->stash->{customer_id}])->as_string
    );

    print ">>>>>>>>>>>>>>>>>>>>>> PbxExtensionSubscriberEditSubadmin update_fields\n";
    my $profile_set = $c->stash->{subscriber}->provisioning_voip_subscriber->voip_subscriber_profile_set;
    print ">>>>>>>>>>>>>>>>>>>>>> got profile set?\n";
    if($profile_set && $self->field('profile')) {
        print ">>>>>>>>>>>>>>>>>>>>>> yes, got profile set\n";
        $self->field('profile')->field('id')->ajax_src(
            $c->uri_for_action('/subscriberprofile/profile_ajax', [$profile_set->id])->as_string
        );
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
