package NGCP::Panel::Controller::API::SoundFileRecordings;
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
    return 'Defines the actual recording of sound files.';
};

sub query_params {
    return [
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SoundFiles/;

sub resource_name{
    return 'soundfilerecordings';
}

sub dispatch_path{
    return '/api/soundfilerecordings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-soundfilerecordings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
