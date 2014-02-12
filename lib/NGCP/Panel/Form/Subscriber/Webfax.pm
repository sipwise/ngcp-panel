package NGCP::Panel::Form::Subscriber::Webfax;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+enctype' => ( default => 'multipart/form-data');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'destination' => (
    type => 'Text',
    label => 'Destination Number',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number to send the fax to']
    },
);

has_field 'data' => (
    type => 'TextArea',
    label => 'Content',
    cols => 200,
    rows => 10,
    maxlength => '1048576', # 1MB
    element_class => [qw/ngcp-autoconf-area/],
);

has_field 'faxfile' => (
    type => 'Upload',
    max_size => 67108864,
    label => 'or File',
    element_attr => {
        rel => ['tooltip'],
        title => ['Supported File Types are TXT, PDF, PS, TIFF']
    },
);

has_field 'save' => (
    type => 'Submit',
    value => 'Send',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/destination data faxfile/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub validate {
    my $self = shift;
    my $data = $self->field('data')->value;
    my $upload = $self->field('faxfile')->value;

    unless($data || $upload) {
        $self->field('faxfile')->add_error("You need to specify a file to fax, if no text is entered in the content field");
    }
}

1;
# vim: set tabstop=4 expandtab:
