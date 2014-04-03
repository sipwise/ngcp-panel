package NGCP::Panel::Form::InvoiceTemplate::Basic;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ValidatorBase';

use Moose::Util::TypeConstraints;
use HTML::FormHandler::Widget::Block::Bootstrap;
enum 'TemplateType' => [ qw/svg html/ ];#html
enum 'TemplateTypeOutput' => [ qw/svg html pdf json svgzip htmlzip pdfzip/ ];#html
enum 'TemplateViewMode' => [ qw/raw parsed both/ ];
enum 'TemplateSourceState' => [ qw/saved previewed default/ ];
#no Moose::Util::TypeConstraints;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+use_fields_for_input_without_param' => ( default => 1 );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'submitid' => ( type => 'Hidden' );
has_field 'tt_type' => (
    type => 'Text',
    required => 1,
    default => 'svg',
    apply => [ 
        { type => 'TemplateType' },
    ],
);

has_field 'tt_output_type' => (
    type => 'Text',
    required => 1,
    default => 'svg',
    apply => [ 
        { type => 'TemplateTypeOutput' },
    ],
);

has_field 'tt_viewmode' => (
    type => 'Text',
    required => 0,
    apply => [ 'TemplateViewMode' ],
    #check => [ qw/raw parsed/ ],
    default => 'parsed',
);

has_field 'tt_sourcestate' => (
    type => 'Text',
    required => 1,
    default => 'saved',
    apply => [ 'TemplateSourceState' ],
    #check => [ qw/saved previewed/ ],
);

has_field 'tt_string' => (
    type     => 'Text',
    #default  => \&
    #apply    => [ { check => \&validate_tt_string } ],
    required => 0,
);

has_field 'contract_id' => (
    type     => 'Hidden',
    #default  => \&
    #apply    => [ { check => \&validate_tt_string } ],
    required => 1,
);

has_field 'tt_id' => (
    type     => 'Hidden',
    #default  => \&
    #apply    => [ { check => \&validate_tt_string } ],
    required => 0,
);
has_field 'name' => (
    type     => 'Text',
    #default  => '',
    #apply    => [ { check => \&validate_tt_string } ],
    required => 1,
);
has_field 'is_active' => (
    type     => 'Checkbox',
    default  => '0',
    #apply    => [ { check => \&validate_tt_string } ],
    required => 0,
);

has_field 'save' => (
    type => 'Button',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name tt_id is_active submitid contract_id/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

=head1 NAME

NGCP::Panel::Form::InvoiceTemplate

=head1 DESCRIPTION

Form to modify an invoice template.

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
