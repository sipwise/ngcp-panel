package NGCP::Panel::Controller::API::FaxRecordings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/OPTIONS/];
}

sub api_description {
    return 'Defines the actual recording of fax messages. It is referred to by the <a href="#faxes">Faxes</a> relation. A GET on an item returns the fax in the binary format as image/tif. Additional formats are also supported for download (see: the query_params option).';
};

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::FaxRecordings/;

sub resource_name{
    return 'faxrecordings';
}

sub dispatch_path{
    return '/api/faxrecordings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-faxrecordings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/fax/],
});

1;

# vim: set tabstop=4 expandtab:
