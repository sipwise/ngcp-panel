package NGCP::Panel::Form::Customer::PbxSubscriberEdit;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

use NGCP::Panel::Field::PbxGroup;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

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

has_field 'email' => (
    type => 'Email',
    required => 0,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email address of the subscriber.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/e164 alias_number alias_number_add email webusername webpassword password status profile_set profile/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub update_fields {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);

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
