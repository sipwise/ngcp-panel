package NGCP::Panel::Form::Device::ModelAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Device::Model';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this device model belongs to.'],
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
    render_list => [qw/reseller vendor model type extensions_num connectable_models linerange linerange_add bootstrap_method bootstrap_uri bootstrap_config_http_sync_method bootstrap_config_http_sync_uri bootstrap_config_http_sync_params bootstrap_config_redirect_panasonic_user bootstrap_config_redirect_panasonic_password bootstrap_config_redirect_yealink_user bootstrap_config_redirect_yealink_password bootstrap_config_redirect_polycom_user bootstrap_config_redirect_polycom_password bootstrap_config_redirect_polycom_profile bootstrap_config_redirect_snom_user bootstrap_config_redirect_snom_password bootstrap_config_redirect_snom_profile bootstrap_config_redirect_snom_product_family bootstrap_config_redirect_grandstream_user bootstrap_config_redirect_grandstream_password bootstrap_config_redirect_ale_user bootstrap_config_redirect_ale_password front_image front_thumbnail mac_image/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
