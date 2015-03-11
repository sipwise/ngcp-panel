package NGCP::Panel::Utils::I18N;

use Sipwise::Base;

sub translate_form {
    my ($self, $c, $form, $extract_strings) = @_;
    if ($extract_strings) {
        return $self->_translate_fields_recursive($c, [$form->fields], $extract_strings);
    }
    $self->_translate_fields_recursive($c, [$form->fields]);
    return $form;
}

sub _translate_fields_recursive {
    my ($self, $c, $fields, $extract_strings) = @_;
    my @strings = ();
    for my $field (@$fields) {
        if ($field->label) {
            push @strings, $field->label if $extract_strings;
            $field->label( $c->loc($field->label) );
        }
        if ($field->isa('HTML::FormHandler::Field::Submit')
                || $field->isa('HTML::FormHandler::Field::Button')) {
            push @strings, $field->value if $extract_strings;
            $field->value( $c->loc($field->value) );
        }
        if ($field->isa('HTML::FormHandler::Field::Select')) {
            for my $option (@{ $field->options }) {
                push @strings, $option->{label} if $extract_strings;
                $option->{label} = $c->loc($option->{label}) if $option->{label};
            }
        }
        if ($field->element_attr->{title}[0]) {
            push @strings, $field->element_attr->{title}[0] if $extract_strings;
            $field->element_attr->{title}[0] = $c->loc($field->element_attr->{title}[0]);
        }
        if ($field->isa('HTML::FormHandler::Field::Compound')) {
            if ($extract_strings) {
                push @strings, @{ $self->_translate_fields_recursive($c,[$field->fields],$extract_strings) };
            } else {
                $self->_translate_fields_recursive($c,[$field->fields]);
            }
        }
        if($field->isa('NGCP::Panel::Field::DataTable')) {
            for my $t (@{ $field->table_titles }) {
                push @strings, $t if $extract_strings;
                $t = $c->loc($t);
            }
            $field->language_file( $c->loc($field->language_file) )
                if ($field->language_file);
        }
    }
    return \@strings if $extract_strings;
    return;
}

1;
