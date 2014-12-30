package NGCP::Panel::Form::Device::ModelAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Device::ModelAdmin';
use Moose::Util::TypeConstraints;

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller vendor model linerange bootstrap_uri bootstrap_method bootstrap_config_http_sync_uri bootstrap_config_http_sync_method bootstrap_config_http_sync_params bootstrap_config_redirect_panasonic_user bootstrap_config_redirect_panasonic_password bootstrap_config_redirect_yealink_user bootstrap_config_redirect_yealink_password bootstrap_config_redirect_polycom_user bootstrap_config_redirect_polycom_password/],
);

override 'field_list' => sub {
    my $self = shift;
    my $c = $self->ctx;
    return unless $c;

    super();
    foreach my $f(qw/front_image mac_image linerange_add/) {
        $self->field($f)->inactive(1);
    }
};

1;
# vim: set tabstop=4 expandtab:
