package NGCP::Panel::Form::Device::Model;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+enctype' => ( default => 'multipart/form-data');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'vendor' => (
    type => 'Text',
    required => 1,
    label => 'Vendor',
);

has_field 'model' => (
    type => 'Text',
    required => 1,
    label => 'Model',
);

has_field 'front_image' => (
    type => 'Upload',
    required => 0,
    label => 'Front Image',
    max_size => '67108864', # 64MB
);

has_field 'mac_image' => (
    type => 'Upload',
    required => 0,
    label => 'MAC Address Image',
    max_size => '67108864', # 64MB
);

has_field 'sync_uri' => (
    type => 'Text',
    required => 0,
    label => 'Bootstrap Sync URI',
    default => 'http://[% client.ip %]/admin/resync',
);

has_field 'sync_method' => (
    type => 'Select',
    required => 0,
    label => 'Bootstrap Sync HTTP Method',
    options => [
        { label => 'GET', value => 'GET' },
        { label => 'POST', value => 'POST' },
    ],
    default => 'GET',
);

has_field 'sync_params' => (
    type => 'Text',
    required => 0,
    label => 'Bootstrap Sync Parameters',
    default => '[% server.uri %]/$MA',
);

has_field 'linerange' => (
    type => 'Repeatable',
    label => 'Line/Key Range',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
);

has_field 'linerange.id' => (
    type => 'Hidden',
);

has_field 'linerange.name' => (
    type => 'Text',
    label => 'Name',
    default => 'Phone Keys',
    element_attr => {
        rel => ['tooltip'],
        title => ['The Name of this range, e.g. Phone Keys or Attendant Console 1 Keys, accessible in the config template array via phone.lineranges[].name'],
    },
);

has_field 'linerange.num_lines' => (
    type => 'PosInteger',
    label => 'Number of Lines/Keys',
    default => 4,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of Lines/Keys in this range, indexed from 0 in the config template array phone.lineranges[].lines[]'],
    },
);

has_field 'linerange.can_private' => (
    type => 'Boolean',
    label => 'Supports Private Line',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Lines/Keys in this range can be used as regular phone lines. Value is accessible in the config template via phone.lineranges[].lines[].can_private'],
    },
);

has_field 'linerange.can_shared' => (
    type => 'Boolean',
    label => 'Supports Shared Line',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Lines/Keys in this range can be used as shared lines. Value is accessible in the config template via phone.lineranges[].lines[].can_shared'],
    },
);

has_field 'linerange.can_blf' => (
    type => 'Boolean',
    label => 'Supports Busy Lamp Field',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Lines/Keys in this range can be used as Busy Lamp Field. Value is accessible in the config template via phone.lineranges[].lines[].can_blf'],
    },
);

has_field 'linerange.rm' => (
    type => 'RmElement',
    value => 'Remove',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'linerange_add' => (
    type => 'AddElement',
    repeatable => 'linerange',
    value => 'Add another Line/Key Range',
    element_class => [qw/btn btn-primary pull-right/],
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
    render_list => [qw/vendor model linerange linerange_add front_image mac_image sync_uri sync_method sync_params/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
