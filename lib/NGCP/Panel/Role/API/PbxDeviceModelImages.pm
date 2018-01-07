package NGCP::Panel::Role::API::PbxDeviceModelImages;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

sub resource_name{
    return 'pbxdevicemodelimages';
}
sub dispatch_path{
    return '/api/pbxdevicemodelimages/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodelimages';
}

sub get_form {
    my ($self, $c) = @_;
    return;
}

1;
# vim: set tabstop=4 expandtab:
