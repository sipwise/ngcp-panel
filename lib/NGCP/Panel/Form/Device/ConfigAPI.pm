package NGCP::Panel::Form::Device::ConfigAPI;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
has '+enctype' => ( default => 'multipart/form-data');
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'device_id' => (
    type => 'PosInteger',
    required => 1,
    label => 'Device Model',
    element_attr => {
        rel => ['tooltip'],
        title => ['The pbx device model id this config belongs to.']
    },
);

has_field 'version' => (
    type => 'Text',
    required => 1,
    label => 'Version',
    element_attr => {
        rel => ['tooltip'],
        title => ['The version number of this config.']
    },
);

has_field 'content_type' => (
    type => 'Text',
    label => 'Filename',
    element_attr => {
        rel => ['tooltip'],
        title => ['The content type this config is served as.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/device_id version content_type/],
);

1;
# vim: set tabstop=4 expandtab:
