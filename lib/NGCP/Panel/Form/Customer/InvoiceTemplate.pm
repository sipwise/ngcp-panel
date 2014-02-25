package NGCP::Panel::Form::Customer::InvoiceTemplate;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use Moose::Util::TypeConstraints;
enum 'TemplateType' => [ qw/svg/ ];#html
enum 'TemplateViewMode' => [ qw/raw parsed/ ];
enum 'TemplateSourceState' => [ qw/saved previewed/ ];
no Moose::Util::TypeConstraints;

#while use only for validation, no rendering is necessary
#use HTML::FormHandler::Widget::Block::Bootstrap;

#looks as often repeated
#has '+widget_wrapper' => ( default => 'Bootstrap' );
#sub build_form_element_class { [qw/form-horizontal/] }

#Attempt to use Moose to validation
#has 'sort_order' => (
#      is  => 'ro',
#      isa => enum([qw[ ascending descending ]]),
#);

has_field 'tt_type' => (
#    is => 'rw',
#    isa => enum([qw[ svg ]]),#html
    type => 'Text',
    required => 0,
    #apply => [ 'enum' ],
    #apply => [ { check => [qw/svg/] } ],
    apply => [ 'TemplateType' ],
    
);

has_field 'tt_viewmode' => (
    type => 'Text',
    required => 0,
);

has_field 'tt_sourcestate' => (
    type => 'Text',
    required => 1,
);

1;

=head1 NAME

NGCP::Panel::Form::InvoiceTemplate

=head1 DESCRIPTION

Form to modify a invoice template.

=head1 METHODS

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
