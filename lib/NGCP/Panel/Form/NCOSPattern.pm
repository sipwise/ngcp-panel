package NGCP::Panel::Form::NCOSPattern;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Model::DBIC';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    required => 1,
);

has_field 'description' => (
    type => 'Text',
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
    render_list => [qw/pattern description/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::NCOSPattern

=head1 DESCRIPTION

Form to modify a billing.ncos_pattern_list row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
