package NGCP::Panel::Form::Pbx::UserAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'id' => (
    type => 'Hidden',
    element_attr => {
        rel => ['tooltip'],
        title => ['The internal id of the pbx user'],
    },
);

has_field 'primary_number' => (
    type => '+NGCP::Panel::Field::E164',
    order => 99,
    required => 0,
    label => 'E164 Number',
    do_label => 1,
    do_wrapper => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The main E.164 number (containing a cc, ac and sn attribute) used for inbound and outbound calls.']
    },
);

has_field 'display_name' => (
    type => 'Text',
    label => 'Display Name',
    element_attr => {
        rel => ['tooltip'],
        title => ['The person\'s name, which is then used in auto-provisioned phones, and which can be used as network-provided display name in SIP calls.']
    },
    maxlength => 128,
);

has_field 'pbx_extension' => (
    type => 'Text',
    label => 'PBX Extension',
    element_attr => {
        rel => ['tooltip'],
        title => ['The PBX extension used for short dialling. If provided, the primary number will automatically be derived from the pilot subscriber\'s primary number suffixed by this extension.']
    },
);

has_field 'username' => (
    type => '+NGCP::Panel::Field::Identifier',
    label => 'SIP Username',
    element_attr => {
        rel => ['tooltip'],
        title => ['The username for SIP services.']
    },
);

has_field 'domain' => (
    type => '+NGCP::Panel::Field::Domain',
    label => 'SIP Domain',
    element_attr => {
        rel => ['tooltip'],
        title => ['The domain id this subscriber belongs to.'],
        implicit_parameter => {
            type => "String",
            required => 0,
            validate_when_empty => 0,
            element_attr => {
                title => ['The domain name this subscriber belongs to.'],
            },
        },
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id primary_number display_name pbx_extension username domain/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

__END__

=head1 NAME

NGCP::Panel::Form::Pbx::UserAPI

=head1 DESCRIPTION

A helper to manipulate the subscriber forms

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
