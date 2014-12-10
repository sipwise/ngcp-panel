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
    element_attr => {
        rel => ['tooltip'],
        title => ['The vendor name of this device.'],
        javascript => ' onchange="vendor2bootstrapMethod(this);" ',
    },
);

has_field 'model' => (
    type => 'Text',
    required => 1,
    label => 'Model',
    element_attr => {
        rel => ['tooltip'],
        title => ['The model name of this device.'],
    },
);

has_field 'front_image' => (
    type => 'Upload',
    required => 1,
    label => 'Front Image',
    max_size => '67108864', # 64MB
);

has_field 'mac_image' => (
    type => 'Upload',
    required => 0,
    label => 'MAC Address Image',
    max_size => '67108864', # 64MB
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
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of line/key definitions for this device. Each element is a hash containing the keys name, can_private, can_shared, can_blf and keys (which in turn is an array of hashes having x, y and labelpos allowing top, bottom, left right).'],
    },
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

has_field 'linerange.keys' => (
    type => 'Repeatable',
    label => 'Key Definition',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-nested-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ['The position of the keys on the front image. Attributes are x, y, labelpos (how the label for the key is displayed in the web interface, relative to the given coordinates; one of top, bottom, left, right).'],
    },
);

has_field 'linerange.keys.id' => (
    type => 'Hidden',
);

has_field 'linerange.keys.x' => (
    type => 'PosInteger',
    label => 'x',
    default => 0,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Position of label in frontimage in px from left.'],
    },
);

has_field 'linerange.keys.y' => (
    type => 'PosInteger',
    label => 'y',
    default => 0,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Position of label in frontimage in px from top.'],
    },
);

has_field 'linerange.keys.labelpos' => (
    type => 'Select',
    label => 'Orientation',
    default => 'top',
    required => 1,
    options => [
        { label => 'top', value => 'top' },
        { label => 'bottom', value => 'bottom' },
        { label => 'left', value => 'left' },
        { label => 'right', value => 'right' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Position of label text relative to label arrow.'],
    },
);

has_field 'linerange.keys.rm' => (
    type => 'RmElement',
    value => 'Remove Key',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'linerange.keys_add' => (
    type => 'AddElement',
    repeatable => 'keys',
    value => 'Add Key',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'linerange.rm' => (
    type => 'RmElement',
    value => 'Remove Range',
    order => 100,
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'linerange_add' => (
    type => 'AddElement',
    repeatable => 'linerange',
    value => 'Add another Line/Key Range',
    element_class => [qw/btn btn-primary pull-right/],
);

has_field 'bootstrap_method' => (
    type => 'Select',
    required => 1,
    label => 'Bootstrap Method',
    options => [
        { label => 'Cisco', value => 'http' },
        { label => 'Panasonic', value => 'redirect_panasonic' },
        { label => 'Yealink', value => 'redirect_yealink' },
    ],
    default => 'http',
    element_attr => {
        rel => ['tooltip'],
        title => ['Method to configure the provisioning server on the phone. One of http, redirect_panasonic, redirect_yealink.'],
        # TODO: ????
        javascript => ' onchange="bootstrapDynamicFields(this.options[this.selectedIndex].value);" ',
    },
);
has_field 'bootstrap_uri' => (
    type => 'Text',
    required => 0,
    label => 'Bootstrap URI',
    default => '',
    element_attr => {
        rel => ['tooltip'],
        title => ['Custom provisioning server URI.'],
    },
);


has_field 'bootstrap_config_http_sync_uri' => (
    type => 'Text',
    required => 0,
    label => 'Bootstrap Sync URI',
    default => 'http://[% client.ip %]/admin/resync',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-http/],
    element_attr => {
        rel => ['tooltip'],
        title => ['The sync URI to set the provisioning server of the device (e.g. http://client.ip/admin/resync. The client.ip variable is automatically expanded during provisioning time.'],
    },
);

has_field 'bootstrap_config_http_sync_method' => (
    type => 'Select',
    required => 0,
    label => 'Bootstrap Sync HTTP Method',
    options => [
        { label => 'GET', value => 'GET' },
        { label => 'POST', value => 'POST' },
    ],
    default => 'GET',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-http/],
    element_attr => {
        rel => ['tooltip'],
        title => ['The HTTP method to set the provisioning server (one of GET, POST).'],
    },
);

has_field 'bootstrap_config_http_sync_params' => (
    type => 'Text',
    required => 0,
    label => 'Bootstrap Sync Parameters',
    default => '[% server.uri %]/$MA',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-http/],
    element_attr => { 
        rel => ['tooltip'],
        title => ['The parameters appended to the sync URI when setting the provisioning server, e.g. server.uri/$MA. The server.uri variable is automatically expanded during provisioning time.'],
    },
);
has_field 'bootstrap_config_redirect_panasonic_user' => (
    type => 'Text',
    required => 0,
    label => 'Panasonic username',
    default => '',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-redirect_panasonic/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Username used to configure bootstrap url on Panasonic redirect server. Obtained from Panasonic.'],
    },
);
has_field 'bootstrap_config_redirect_panasonic_password' => (
    type => 'Text',
    required => 0,
    label => 'Panasonic password',
    default => '',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-redirect_panasonic/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Password used to configure bootstrap url on Panasonic redirect server. Obtained from Panasonic.'],
    },
);
has_field 'bootstrap_config_redirect_yealink_user' => (
    type => 'Text',
    required => 0,
    label => 'Yealink username',
    default => '',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-redirect_yealink/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Username used to configure bootstrap url on Yealink redirect server. Obtained from Yealink.'],
    },
);
has_field 'bootstrap_config_redirect_yealink_password' => (
    type => 'Text',
    required => 0,
    label => 'Yealink password',
    default => '',
    wrapper_class => [qw/ngcp-bootstrap-config ngcp-bootstrap-config-redirect_yealink/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Password used to configure bootstrap url on Yealink redirect server. Obtained from Yealink.'],
    },
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
    render_list => [qw/vendor model linerange linerange_add bootstrap_uri bootstrap_method bootstrap_config_http_sync_uri bootstrap_config_http_sync_method bootstrap_config_http_sync_params bootstrap_config_redirect_panasonic_user bootstrap_config_redirect_panasonic_password bootstrap_config_redirect_yealink_user bootstrap_config_redirect_yealink_password front_image mac_image/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

sub field_list {
    my ($self) = @_;

    my $c = $self->ctx;
    return unless($c);

    if($c->stash->{edit_model}) {
        $self->field('front_image')->required(0);
    }
}

1;
# vim: set tabstop=4 expandtab:
