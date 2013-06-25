package NGCP::Panel::Form::SoundFile;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Model::DBIC';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+enctype' => ( default => 'multipart/form-data');
has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'loopplay' => (
    type => 'Boolean',
);

has_field 'soundfile' => (
    type => 'Upload',
    noupdate => 1, #let controller handle the file
    max_size => undef,
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
    render_list => [qw/loopplay soundfile/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::SoundFile

=head1 DESCRIPTION

Form to modify a provisioning.voip_sound_files row.

=head1 METHODS

=head1 AUTHOR

Gerhard Jungwirth

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
