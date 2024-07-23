package NGCP::Panel::Controller::API::ResellerBrandings;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ResellerBrandings/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

__PACKAGE__->set_config({
    POST => {
        'ContentType' => ['multipart/form-data'],
        'Uploads'     => [qw/logo/],
    },
    allowed_roles => {
        'Default' => [qw/admin reseller subscriberadmin subscriber/],
        'POST'    => [qw/admin reseller/],
    },
    required_licenses => {
        POST => [qw/reseller/],
    }
});

# curl -v -X POST --user $USER --insecure -F logo=@path/to/logo.png json='{"reseller_id":1, "css":"<css code>", "csc_primary_color":"#AABBCC", "csc_secondary_color":"#AABBCC"}' https://localhost:4443/api/resellerbrandings/

sub api_description {
    return 'Specifies a model to be set in <a href="#pbxdeviceconfigs">PbxDeviceConfigs</a>. Use a Content-Type "multipart/form-data", provide logo with the actual images, and an additional json part with the properties specified below, e.g.: <code>curl -X POST --user $USER -F logo=@/path/to/logo.png -F json=\'{"reseller_id":...}\' https://example.org:1443/api/resellerbrandings/</code> This resource is read-only to subscribes and subscriberadmins.';
};

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item = $c->model('DB')->resultset('reseller_brandings')->create($resource);

    return $item;
}
1;

# vim: set tabstop=4 expandtab:
