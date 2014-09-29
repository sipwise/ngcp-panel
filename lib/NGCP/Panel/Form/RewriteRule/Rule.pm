package NGCP::Panel::Form::RewriteRule::Rule;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'match_pattern' => (
    type => '+NGCP::Panel::Field::Regexp',
    required => 1,
    inflate_default_method => \&inflate_match_pattern,
    element_attr => {
        rel => ['tooltip'],
        title => ['Match pattern, a regular expression.'],
    },
);

has_field 'replace_pattern' => (
    type => 'Text',
    required => 1,
    label => 'Replacement Pattern',
    inflate_default_method => \&inflate_replace_pattern,
    element_attr => {
        rel => ['tooltip'],
        title => ['Replacement pattern.'],
    },
);

has_field 'description' => (
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
        { label => 'Inbound', value => 'in'},
        { label => 'Outbound', value => 'out'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Inbound (in) or Outbound (out).']
    },
);

has_field 'field' => (
    type => 'Select',
    options => [
        { label => 'Callee', value => 'callee'},
        { label => 'Caller', value => 'caller'},
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['caller or callee.']
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
    render_list => [qw/match_pattern replace_pattern description direction field/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

before 'update_model' => sub {
    my $self = shift;
    $self->value->{match_pattern} =~   s/\$\{(\w+)\}/\$avp(s:$1)/g;
    $self->value->{match_pattern} =~   s/\@\{(\w+)\}/\$(avp(s:$1)[*])/g;
    $self->value->{replace_pattern} =~ s/\$\{(\w+)\}/\$avp(s:$1)/g;
};

sub inflate_match_pattern {
    my ($self, $value) = @_;
    
    $value =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
    $value =~ s/\$\(avp\(s\:(\w+)\)\[\*\]\)/\@{$1}/g;
    return $value;
}

sub inflate_replace_pattern {
    my ($self, $value) = @_;
    
    $value =~ s/\$avp\(s\:(\w+)\)/\${$1}/g;
    return $value;
}

sub validate {
    my $self = shift;
    my $s = $self->field('match_pattern')->value // "";
    my $r = $self->field('replace_pattern')->value // "";
    my $_ = "";
    my $re = "s/$s/$r/";

    eval { use warnings FATAL => qw(all); m/$re/; };
    
    if( $@ && $self->field('match_pattern')->num_errors < 1 ) {
        my $err_msg = 'Match pattern and Replace Pattern do not work together.';
        $self->field('match_pattern')->add_error($err_msg);
        $self->field('replace_pattern')->add_error($err_msg);
    }
    
    if ( $r =~ m/\$$/ ) {
        $self->field('replace_pattern')->add_error('Cannot end with "$"');
    }

    if ( my ($found) = $r =~ m/^([?])/ ) {
        $self->field('replace_pattern')->add_error("Cannot start with \"$found\"");
    }
    if ( $r =~ m/\s/ ) {
        $self->field('replace_pattern')->add_error("Spaces are not allowed in replacement pattern");
    }

    my @acount;
    @acount = $s =~ /(\@\{\w+\})/g;
    if(@acount > 1) {
        $self->field('match_pattern')->add_error("Cannot use more than one array variable in match pattern");
    }
    @acount = $r =~ /(\@\{\w+\})/g;
    if(@acount > 0) {
        $self->field('match_pattern')->add_error("Cannot use array variable in replacement pattern");
    }
}

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
