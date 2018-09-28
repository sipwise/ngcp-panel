package NGCP::Panel::Field::DateTimePicker;
use HTML::FormHandler::Moose;
use Template;
extends 'HTML::FormHandler::Field';

has '+widget' => (default => ''); # leave this empty, as there is no widget ...
has 'template' => ( isa => 'Str',
                    is => 'rw',
                    default => 'helpers/datetimepicker.tt' );
has 'language_file' => (isa => 'Str', is => 'rw', default => 'dataTables.default.js' );
has 'date_format_js' => (isa => 'Str', is => 'rw', default => 'yy-mm-dd' );
has 'time_format_js' => (isa => 'Str', is => 'rw', default => 'HH:mm:ss' );

sub render_element {
    my ($self) = @_;
    my $output = '';

    (my $fieldname = $self->html_name) =~ s!\.!!g;

    my $vars = {
        label => $self->label,
        field_name => $self->html_name,
        field_id => $fieldname . "_datetimepicker",
        value => $self->value,
        date_format_js => $self->date_format_js,
        time_format_js => $self->time_format_js,
        errors => $self->errors,
        language_file => $self->language_file,
    };
    my $t = new Template({ 
        ABSOLUTE => 1, 
        INCLUDE_PATH => [
            '/usr/share/ngcp-panel/templates',
            'share/templates',
        ],
    });

    $t->process($self->template, $vars, \$output) or
        die "Failed to process DateTimePicker field template: ".$t->error();

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

    if($self->required &&
        ( !defined $self->value || !length($self->value) || $self->value !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/ ) ) {
        return $self->add_error("Invalid datetime, must be in format YYYY-mm-DD HH:MM:SS");
    }
    return 1;
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
