package NGCP::Panel::Form::NCOS::ResellerLevel;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'level' => (
    type => 'Text',
    label => 'Level Name',
    required => 1,
    maxlength => 31,
);

has_field 'mode' => (
    type => 'Select',
    options => [
        {value => 'whitelist', label => 'whitelist'},
        {value => 'blacklist', label => 'blacklist'},
    ],
);

has_field 'description' => (
    type => 'Text',
    required => 0,
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
    render_list => [qw/level mode description/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::NCOSLevel

=head1 DESCRIPTION

Form to modify a billing.ncos_levels row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
