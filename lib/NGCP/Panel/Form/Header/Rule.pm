package NGCP::Panel::Form::Header::Rule;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { label => 'Inbound', value => 'inbound' },
        { label => 'Local', value => 'local' },
        { label => 'Peer', value => 'peer' },
        { label => 'Outbound', value => 'outbound' },
    ],
    label => 'Direction',
    required => 1,
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'stopper' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Controls whether next rule is processed if the current one fails.'],
    },
);

has_field 'enabled' => (
    type => 'Boolean',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enables or disables the rule from being included in the headers processing logic'],
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
    render_list => [qw/name direction description stopper enabled/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::RewriteRule

=head1 DESCRIPTION

Form to modify a provisioning.rewrite_rules row.

=head1 METHODS

=head2 inflate_pattern

Inflates match_pattern and replace_pattern from the database by using a
regex before their display.

=head2 validate

Do some special validation for match_pattern and replace_pattern together:

=over

=item replacement pattern ending with C<$>

=item replacement pattern starting with C<*?>

=item replacement pattern containing space

=item General perl validation of the whole regexp

=back

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
