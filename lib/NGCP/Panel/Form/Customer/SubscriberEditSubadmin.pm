package NGCP::Panel::Form::Customer::SubscriberEditSubadmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::SubscriberEdit';

use NGCP::Panel::Utils::Form;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}


has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/email webusername webpassword password lock status external_id timezone/ ],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub update_fields {
    my $self = shift;
    # my $c = $self->ctx;
    # return unless $c;

    $self->field('profile_set')->inactive(1);
    $self->field('profile')->inactive(1);
}

1;

# vim: set tabstop=4 expandtab:
