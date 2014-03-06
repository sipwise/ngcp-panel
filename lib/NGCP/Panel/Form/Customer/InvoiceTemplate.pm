package NGCP::Panel::Form::Customer::InvoiceTemplate;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use Moose::Util::TypeConstraints;
enum 'TemplateType' => [ qw/svg html svgpdf/ ];#html
enum 'TemplateTypeOutput' => [ qw/svg html pdf/ ];#html
enum 'TemplateViewMode' => [ qw/raw parsed/ ];
enum 'TemplateSourceState' => [ qw/saved previewed default/ ];
#no Moose::Util::TypeConstraints;

has '+use_fields_for_input_without_param' => ( default => 1 );

has_field 'tt_type' => (
    type => 'Text',
    required => 1,
    default => 'svg',
    apply => [ 
        { type => 'TemplateType' },
        #{ transform => sub{ $_[0] eq 'svgpdf' and return 'svg'; } },
    ],
);

has_field 'tt_output_type' => (
    type => 'Text',
    required => 1,
    default => 'svg',
    apply => [ 
        { type => 'TemplateTypeOutput' },
        #{ when => { tt_type => 'svgpdf' }, transform => sub{ 'pdf' } },
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

#sub validate_tt_string{
    #here could be following: take default from file and get all variables and validate variables from customer string
#};
sub validate_tt_type {
    my ( $self, $field ) = @_; # self is the form
    use irka;
    use Data::Dumper;
    irka::loglong("\n\n\nin validate\naaaaaaaaaaaaaaaaaaaaa\naaaaaaaaaaaaaaa\n");
    die();
    if( $self->field('tt_type')->value eq 'svgpdf'){
        $self->field('tt_output_type')->value('pdf');
        $self->field('tt_type')->value('svg');
    }
    return 1;
};
sub validate {
    my $self = shift;
    use irka;
    use Data::Dumper;
    irka::loglong("\n\n\nin validate\naaaaaaaaaaaaaaaaaaaaa\naaaaaaaaaaaaaaa\n");
    die();
    if( $self->field('tt_type')->value eq 'svgpdf'){
        $self->field('tt_output_type')->value('pdf');
        $self->field('tt_type')->value('svg');
    }
    return 1;
}

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
