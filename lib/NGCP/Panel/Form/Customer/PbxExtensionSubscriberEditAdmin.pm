package NGCP::Panel::Form::Customer::PbxExtensionSubscriberEditAdmin;

use HTML::FormHandler::Moose;
use NGCP::Panel::Field::PosInteger;
extends 'NGCP::Panel::Form::Customer::PbxExtensionSubscriberEdit';

with 'NGCP::Panel::Render::RepeatableJs';

has_field 'extension' => (
    required => 0,
);

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164',
    order => 99,
    required => 0,
    label => 'E164 Number',
    do_label => 1,
    do_wrapper => 1,
);

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
    render_list => [qw/group e164 alias_number alias_number_add display_name webusername webpassword password status external_id/ ],
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
