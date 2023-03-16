package NGCP::Panel::Form::Sound::ResellerSet;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'contract' => (
    type => '+NGCP::Panel::Field::PbxCustomerContract',
    label => 'Customer',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract this sound set belongs to. If set, the sound set becomes a customer sound set instead of a system sound set.'],
    },
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the sound set'],
    },
);

has_field 'description' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The description of the sound set'],
    },
);

has_field 'expose_to_customer' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Allow customers to use this sound set'],
    },
);

has_field 'contract_default' => (
    type => 'Boolean',
    label => 'Default for Subscribers',
    element_attr => {
        rel => ['tooltip'],
        title => ['If active and a customer is selected, this sound set is used for all existing and new subscribers within this customer if no specific sound set is specified for the subscribers'],
    },
);

has_field 'parent' => (
    type => '+NGCP::Panel::Field::ParentSoundSet',
    label => 'Parent',
    validate_when_empty => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Parent sound set. If used, missing sound of the current sound set will used from the parent one (except for those with use_parent = 0)'],
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
    render_list => [qw/contract name description expose_to_customer contract_default parent/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::SoundSet

=head1 DESCRIPTION

Form to modify a provisioning.voip_sound_sets row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
