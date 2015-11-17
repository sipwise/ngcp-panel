package NGCP::Panel::Form::Device::Config;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'device' => (
    type => '+NGCP::Panel::Field::Device',
    validate_when_empty => 1,
    label => 'Device Model',
);

has_field 'version' => (
    type => 'Text',
    required => 1,
    label => 'Version',
);

has_field 'content_type' => (
    type => 'Text',
    required => 1,
    label => 'Content Type',
    default => 'text/xml',
);

has_field 'data' => (
    type => 'TextArea',
    required => 1,
    label => 'Content',
    cols => 200,
    rows => 10,
    maxlength => '67108864', # 64MB
    element_class => [qw/ngcp-autoconf-area/],
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
    render_list => [qw/device version content_type data/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
