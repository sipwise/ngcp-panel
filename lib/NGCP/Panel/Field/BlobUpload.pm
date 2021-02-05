package NGCP::Panel::Field::BlobUpload;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'show_data' => (
    type => 'Button',
    label => '',
    value => "Show Data",
    element_class => [qw/ngcp-blob-show-data/],
    element_attr => {
        readonly => 1,
        rel => ['tooltip'],
        title => ['Show/hide file content.'],
    },
);

has_field 'content_data' => (
    type => 'TextArea',
    label => 'Content Data',
    default => '',
    cols => 200,
    rows => 10,
    maxlength => '16777216', # 16MB
    element_class => [qw/ngcp-blob-data-area/],
    element_attr => {
        readonly => 1
    },
    inflate_default_method => \&inflate_content_data_field,
);

has_field 'content_type' => (
    type => 'Text',
    label => 'Content Type',
    default => 'application/octet-stream',
    element_attr => {
        rel => ['tooltip'],
        title => ['The content type of this file.']
    },
    inflate_default_method => \&inflate_content_type_field,
);

has_field 'file' => (
    type => 'Upload',
    label => 'File',
    max_size => '16777216', # MEDIUMBLOB max size
);

has_field 'delete' => (
    type => 'Submit',
    value => 'Delete',
    element_class => [qw/btn btn-secondary/],
    label => '',
);

has_field 'download' => (
    type => 'Submit',
    value => 'Download',
    element_class => [qw(btn btn-tertiary pull-right)],
    label => '',
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/delete download/],
);

sub inflate_content_data_field {
    my ($self, $value) = @_;

    my $c = $self->form->ctx;
    my $preference = $c->stash->{preference}->first // return $value;

    if ($preference->blob) {
        if ($preference->blob->content_type =~ /^(text|aplication\/json)/) {
            my %pref_data = $preference->get_inflated_columns;
            return $pref_data{short_blob_value}
        } else {
            return "#binary-data#";
        }
    }
    return $value;
}

sub inflate_content_type_field {
    my ($self, $value) = @_;

    my $c = $self->form->ctx;
    my $preference = $c->stash->{preference}->first // return $value;

    if ($preference->blob) {
        return $preference->blob->content_type;
    }
    return $value;
}

no Moose;
1;
