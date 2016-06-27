package NGCP::Panel::Field::DataTable;
use HTML::FormHandler::Moose;
use Template;
use JSON;
use URI::Encode;

extends 'HTML::FormHandler::Field';

has '+widget' => (default => ''); # leave this empty, as there is no widget ...
has 'template' => ( isa => 'Str',
                    is => 'rw',
                    default => 'helpers/datatables_field.tt' );
has 'ajax_src' => ( isa => 'Str', is => 'rw', default => '/emptyajax' );
has 'table_fields' => ( isa => 'ArrayRef', is => 'rw' );
has 'table_titles' => ( isa => 'ArrayRef', is => 'rw' );
has 'custom_renderers' => ( isa => 'HashRef', is => 'rw' );
has 'no_ordering' => ( isa => 'Bool', is => 'rw' );
has 'language_file' => (isa => 'Str', is => 'rw', default => 'dataTables.default.js' );
has 'search_tooltip' => (isa => 'Str', is => 'rw', default => 'Filter for column values matching the pattern string, e.g. 12*45. The * (wildcard) is implicitly prepended and appended.' );

#didn't want to incude some complex role related logic here,
#as these DataTable fields also are used in API
#To don't slow down API
#traits  => ['Code']
has 'adjust_datatable_vars' => ( isa => 'CodeRef', is => 'rw' );

sub render_element {
    my ($self) = @_;
    my $output = '';

    (my $tablename = $self->html_name) =~ s!\.!!g;
    my $vars = {
        label => $self->label,
        field_name => $self->html_name,
        table_id => $tablename . "table",
        hidden_id => $tablename . "hidden",
        value => $self->value,
        ajax_src => $self->ajax_src,
        table_fields => $self->table_fields,
        table_titles => $self->table_titles,
        custom_renderers => $self->custom_renderers,
        no_ordering => $self->no_ordering,
        errors => $self->errors,
        language_file => $self->language_file,
        search_tooltip => $self->search_tooltip,
        wrapper_class => ref $self->wrapper_class eq 'ARRAY' ? join (' ', @{$self->wrapper_class}) : $self->wrapper_class,
    };
    ref $self->adjust_datatable_vars eq 'CODE' and $self->adjust_datatable_vars->($self, $vars);

    my $t = new Template({
        ABSOLUTE => 1,
        INCLUDE_PATH => [
            '/media/sf_/VMHost/ngcp-panel/share/templates',
            '/usr/share/ngcp-panel/templates',
            'share/templates',
        ],
    });

    $t->process($self->template, $vars, \$output) or
        die "Failed to process Datatables field template: ".$t->error();

    #print $output;

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
        ( !defined($self->value) || !length($self->value) ) ) {
        return $self->add_error($self->label . " is invalid");
    }
    return 1;
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
