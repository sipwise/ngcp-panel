package NGCP::Panel::Form::Customer::PbxAdminSubscriber;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxSubscriber';

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164',
    order => 99,
    required => 0,
    label => 'E.164 Number',
    do_label => 1,
    do_wrapper => 1,
);

has_field 'e164range' => (
    type => '+NGCP::Panel::Field::E164RangeRepeat',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'e164range_add' => (
    type => 'AddElement',
    repeatable => 'e164range',
    value => 'Add another range',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'domain' => (
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    validate_when_empty => 1,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/domain e164 e164range e164range_add display_name email webusername webpassword username password administrative status external_id profile_set/ ],
);

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
