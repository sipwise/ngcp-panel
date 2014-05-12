package NGCP::Panel::Field::DatePicker;
use HTML::FormHandler::Moose;
use Template;
extends 'HTML::FormHandler::Field';

has '+widget' => (default => ''); # leave this empty, as there is no widget ...
has 'template' => ( isa => 'Str',
                    is => 'rw',
                    default => 'helpers/datepicker.tt' );
has 'language_file' => (isa => 'Str', is => 'rw', default => 'dataTables.default.js' );
has 'date_format_js' => (isa => 'Str', is => 'rw', default => 'yy-mm-dd' );

sub render_element {
    my ($self) = @_;
    my $output = '';

    (my $fieldname = $self->html_name) =~ s!\.!!g;

    my $vars = {
        label => $self->label,
        field_name => $self->html_name,
        field_id => $fieldname . "_datepicker",
        value => $self->value,
        date_format_js => $self->date_format_js,
        errors => $self->errors,
        language_file => $self->language_file,
    };
    my $t = new Template({ 
        ABSOLUTE => 1, 
        INCLUDE_PATH => [
            '/usr/share/ngcp-panel1444/templates',
            'share/templates',
        ],
    });

    $t->process($self->template, $vars, \$output) or
        die "Failed to process Datepicker field template: ".$t->error();

    return $output;
}

sub render {
    my ( $self, $result ) = @_;
    $result ||= $self->result;
    die "No result for form field '" . $self->full_name . "'. Field may be inactive." unless $result;
    return $self->render_element( $result );
}

sub validate {
    my ( $self ) = @_;

    return $self->add_error($self->label . " is invalid")
        if($self->required and (
            !defined $self->value or !length($self->value)
        ));
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
