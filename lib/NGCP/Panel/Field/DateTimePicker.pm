package NGCP::Panel::Field::DateTimePicker;
use HTML::FormHandler::Moose;
use Template;
use NGCP::Panel::Utils::DateTime;
extends 'HTML::FormHandler::Field';

has '+widget' => (default => ''); # leave this empty, as there is no widget ...
has 'template' => ( isa => 'Str',
                    is => 'rw',
                    default => 'helpers/datetimepicker.tt' );
has 'language_file' => (isa => 'Str', is => 'rw', default => 'dataTables.default.js' );
has 'date_format_js' => (isa => 'Str', is => 'rw', default => 'yy-mm-dd' );
has 'time_format_js' => (isa => 'Str', is => 'rw', default => 'HH:mm:ss' );
has 'options'        => (isa => 'HashRef', is => 'rw', default => sub { {} } );
has 'no_date_picker' => (isa => 'Bool', is => 'rw', default => 0 );
has 'no_time_picker' => (isa => 'Bool', is => 'rw', default => 0 );

has '+deflate_method' => ( default => sub { \&datetime_deflate } );
#has '+inflate_method' => ( default => sub { \&datetime_inflate } );

sub render_element {
    my ($self) = @_;
    my $output = '';

    (my $fieldname = $self->html_name) =~ s!\.!!g;

    #we are after default processing here
    if ($self->value && $self->value eq 'now') {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        #todo -  consider js datetime format
        $self->value($now->ymd);
    }

    my $vars = {
        label => $self->label,
        do_label => $self->do_label,
        field_name => $self->html_name,
        field_id => $fieldname . "_datetimepicker",
        value => $self->value,
        date_format_js => $self->date_format_js,
        time_format_js => $self->time_format_js,
        errors => $self->errors,
        language_file => $self->language_file,
        options => $self->options,
        no_date_picker => $self->no_date_picker,
        no_time_picker => $self->no_time_picker,
        wrapper_class => $self->wrapper_class,
        field => $self
    };
    my $t = new Template({ 
        ABSOLUTE => 1, 
        INCLUDE_PATH => [
            '/media/sf_/VMHost/ngcp-panel/share/templates',
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
        ( !defined $self->value || !length($self->value) ) ) {
        return $self->add_error("Invalid datetime, must be in format ".$self->date_format_js." ".$self->time_format_js);
    }
    # || $self->value !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/
    if ($self->no_date_picker) {
        if ($self->value !~ /^\d{2}:\d{2}:\d{2}$/) {
            return $self->add_error("Invalid time, must be in format ".$self->time_format_js);
        }
    } else {
        if (!NGCP::Panel::Utils::DateTime::from_forminput_string($self->value)) {
            return $self->add_error("Invalid datetime, must be in format ".$self->date_format_js." ".$self->time_format_js);
        }
    }
    return 1;
}

sub datetime_deflate {  
    my ( $self, $value ) = @_;

    my $c = $self->form->ctx;

    if(blessed($value) && $value->isa('DateTime')) {
        if($c && $c->session->{user_tz}) {
            $value->set_time_zone('local');                 # starting point for conversion
            $value->set_time_zone($c->session->{user_tz});  # desired time zone
        }
        if ($self->no_time_picker) {
            return $value->ymd('-');
        } elsif ($self->no_date_picker) {
            return $value->hms(':');
        } else {
            return $value->ymd('-') . ' ' . $value->hms(':');
        }
    } else {
        return $value;
    }
}

sub combine_datetime {  # method should be called after form processing, when both date and time fields have values
    my ( $self, $value ) = @_;
    my $form = $self->form;
    my $c = $self->form->ctx;

    my $tz;
    if($c && $c->session->{user_tz}) {
        $tz = $c->session->{user_tz};
    }
    my ($value_res);
    if ($self->no_time_picker) {
        my $time_name = $self->name;
        $time_name =~s/date/time/;
        $self->parent and $time_name = $self->parent->name . '.' . $time_name;
        my $time_field = $form->field($time_name);
        $value_res = $self->value . ($time_field->result && $time_field->result->value ? ' ' : '') . $time_field->result->value;
    } elsif ($self->no_date_picker) {
        my $date_name = $self->name;
        $date_name =~s/time/date/;
        $self->parent and $date_name = $self->parent->name . '.' .  $date_name;
        my $date_field = $form->field($date_name);
        $value_res = ($date_field->result && $date_field->result->value ? $date_field->result->value . ' ' : '') . $self->value;
    } else {
        $value_res = $self->value;
    }
    if (!$self->no_date_picker) {
        my $date = NGCP::Panel::Utils::DateTime::from_forminput_string($self->value, $tz);
        unless ($date) {
            $self->add_error('Could not parse DateTime input.');
            return;
        }
        $date->set_time_zone('local');  # convert to local
    }

    return $value_res;
}
no Moose;
1;

# vim: set tabstop=4 expandtab:
