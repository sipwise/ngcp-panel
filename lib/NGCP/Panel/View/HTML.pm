package NGCP::Panel::View::HTML;
use Sipwise::Base;

use URI::Escape qw/uri_unescape/;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt',
    render_die => 1,
    ENCODING => 'UTF-8',
    WRAPPER => 'wrapper.tt',
    FILTERS => {
        uri_unescape => sub {
            URI::Escape::uri_unescape(@_);
        },
    },
    expose_methods => [qw/translate_form/],
);

sub translate_form {
    my ($self, $c, $form) = @_;
    $self->_translate_fields_recursive($c, [$form->fields]);
    return $form;
}

sub _translate_fields_recursive {
    my ($self, $c, $fields) = @_;
    for my $field (@$fields) {
        $field->label( $c->loc($field->label) )
            if $field->label;
        if ($field->isa('HTML::FormHandler::Field::Submit')
                || $field->isa('HTML::FormHandler::Field::Button')) {
            $field->value( $c->loc($field->value) );
        }
        if ($field->isa('HTML::FormHandler::Field::Select')) {
            for my $option (@{ $field->options }) {
                $option->{label} = $c->loc($option->{label});
            }
        }
        if ($field->element_attr->{title}[0]) {
            $field->element_attr->{title}[0] = $c->loc($field->element_attr->{title}[0]);
        }
        if ($field->isa('HTML::FormHandler::Field::Compound')) {
            $self->_translate_fields_recursive($c,[$field->fields]);
        }
        if($field->isa('NGCP::Panel::Field::DataTable')) {
            for my $t (@{ $field->table_titles }) {
                $t = $c->loc($t);
            }
            $field->language_file( $c->loc($field->language_file) )
                if ($field->language_file);
        }
    }
    return;
}

=head1 NAME

NGCP::Panel::View::HTML - TT View for NGCP::Panel

=head1 DESCRIPTION

TT View for NGCP::Panel.

=head1 SEE ALSO

L<NGCP::Panel>

=head1 AUTHOR

Andreas Granig,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

# vim: set tabstop=4 expandtab:
