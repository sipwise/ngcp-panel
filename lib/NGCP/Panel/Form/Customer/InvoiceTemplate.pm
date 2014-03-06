package NGCP::Panel::Form::Customer::InvoiceTemplate;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use Moose::Util::TypeConstraints;
enum 'TemplateType' => [ qw/svg html/ ];#html
enum 'TemplateViewMode' => [ qw/raw parsed/ ];
enum 'TemplateSourceState' => [ qw/saved previewed default/ ];
no Moose::Util::TypeConstraints;

has '+use_fields_for_input_without_param' => ( default => 1 );

has_field 'tt_type' => (
    type => 'Text',
    required => 1,
    default => 'svg',
    #apply => [ qw/svg/ ],
    apply => [ 'TemplateType' ],
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
    type     => 'Text',
    #default  => \&
    #apply    => [ { check => \&validate_tt_string } ],
    required => 1,
);

has_field 'tt_id' => (
    type     => 'Text',
    #default  => \&
    #apply    => [ { check => \&validate_tt_string } ],
    required => 0,
);

sub validate_tt_string{
    #here could be following: take default from file and get all variables and validate variables from customer string
};

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
