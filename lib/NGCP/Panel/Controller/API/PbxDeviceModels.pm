package NGCP::Panel::Controller::API::PbxDeviceModels;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceModels/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use NGCP::Panel::Utils::Device;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

__PACKAGE__->set_config({
    POST => {
        'ContentType' => ['multipart/form-data'],
        'Uploads'     => [qw/front_image mac_image front_thumbnail/],
    },
    allowed_roles => {
        'Default' => [qw/admin reseller subscriberadmin subscriber/],
        'POST'    => [qw/admin reseller/],
    }
});

# curl -v -X POST --user $USER --insecure -F front_image=@sandbox/spa504g-front.png -F mac_image=@sandbox/spa504g-back.png -F front_thumbnail=@sandbox/spa504g-front-small.png -F json='{"reseller_id":1, "vendor":"Cisco", "model":"SPA999", "linerange":[{"name": "Phone Keys", "can_private":true, "can_shared":true, "can_blf":true, "can_speeddial":true, "can_forward":true, "can_transfer":true, "keys":[{"labelpos":"top", "x":5110, "y":5120},{"labelpos":"top", "x":5310, "y":5320}]}]}' https://localhost:4443/api/pbxdevicemodels/

sub api_description {
    return 'Specifies a model to be set in <a href="#pbxdeviceconfigs">PbxDeviceConfigs</a>. Use a Content-Type "multipart/form-data", provide front_image, front_thumbnail and mac_image parts with the actual images, and an additional json part with the properties specified below, e.g.: <code>curl -X POST --user $USER -F front_image=@/path/to/front.png -F mac_image=@/path/to/mac.png -F front_thumbnail=@/path/to/front-small.png -F json=\'{"reseller_id":...}\' https://example.org:1443/api/pbxdevicemodels/</code> This resource is read-only to subscriberadmins.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for models belonging to a certain reseller',
            query_type => 'string_eq',
        },
        {
            param => 'vendor',
            description => 'Filter for vendor matching a vendor name pattern',
            query_type => 'string_eq',
        },
        {
            param => 'model',
            description => 'Filter for models matching a model name pattern',
            query_type => 'string_like',
        },
    ];
}

sub documentation_sample {
    return  {
        vendor => "testvendor",
        model => "testmodel",
        reseller_id => 1,
        sync_method => "GET",
        sync_params => '[% server.uri %]/$MA',
        sync_uri => 'http://[% client.ip %]/admin/resync',
        linerange => [
            {
                name => "Phone Keys",
                can_private => 1,
                can_shared => 1,
                can_blf => 1,
                can_speeddial => 1,
                can_forward => 1,
                can_transfer => 1,
                keys => [
                    {
                        x => 100,
                        y => 200,
                        labelpos => "left",
                    },
                    {
                        x => 100,
                        y => 300,
                        labelpos => "right",
                    },
                ],
            },
        ],
    } ;
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item = NGCP::Panel::Utils::Device::store_and_process_device_model($c, undef, $resource);

    return $item;
}
1;

# vim: set tabstop=4 expandtab:
