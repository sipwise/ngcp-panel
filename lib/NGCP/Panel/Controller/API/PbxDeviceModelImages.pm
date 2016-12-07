package NGCP::Panel::Controller::API::PbxDeviceModelImages;
use Sipwise::Base;


use parent qw/NGCP::Panel::Role::EntitiesFiles NGCP::Panel::Role::API::PbxDeviceModelImages NGCP::Panel::Role::API::PbxDeviceModels/;


sub allowed_methods{
    return [qw/OPTIONS POST/];
}

sub api_description {
    return 'Used to download the front and mac image of a <a href="#pbxdevicemodels">PbxDeviceModel</a>. Returns a binary attachment with the correct content type (e.g. image/jpeg) of the image.';
};

sub query_params {
    return [
        {
            param => 'type',
            description => 'Either "front" (default) or "mac" to download one or the other.',
            query => {
                # handled directly in role
                first => sub {},
                second => sub {},
            }
        }
    ];
}

#sub create_item :Private {
#    my ($self, $c, $resource, $form, $process_extras) = @_;
#    my $item;
#    my $model = $process_extras->{model};
#    try {
#        $item = $model->autoprov_firmwares->create($resource);
#        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
#    } catch($e) {
#        $c->log->error("failed to create peering group: $e"); # TODO: user, message, trace, ...
#        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering group.");
#        last;
#    }
#    return $item;
#}

1;

# vim: set tabstop=4 expandtab:
