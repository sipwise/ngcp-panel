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
has 'language_file' => (isa => 'Str', is => 'rw', default => 'dataTables.default.js' );

sub render_element {
    my ($self) = @_;
    my $output = '';

    (my $tablename = $self->html_name) =~ s!\.!!g;
    if($self->ajax_src !~/dt_columns/){
        my $i = 0;
        my $dt_columns = [ map {{name=>$_,title=>$self->table_titles->[$i++],}} @{$self->table_fields} ];
        my $decoder = URI::Encode->new;
        $self->ajax_src( $self->ajax_src.($self->ajax_src!~/\?/?'?':'&').'dt_columns='.$decoder->encode(to_json($dt_columns)) );
    }

    my $vars = {
        label => $self->label,
        field_name => $self->html_name,
        table_id => $tablename . "table",
        hidden_id => $tablename . "hidden",
        value => $self->value,
        ajax_src => $self->ajax_src,
        table_fields => $self->table_fields,
        table_titles => $self->table_titles,
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

    use Data::Printer; p $vars;

    $t->process($self->template, $vars, \$output) or
        die "Failed to process Datatables field template: ".$t->error();

    print $output;

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
