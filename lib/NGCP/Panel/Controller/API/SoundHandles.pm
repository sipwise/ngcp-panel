package NGCP::Panel::Controller::API::SoundHandles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Provides a read-only overview of available sound handles and their corresponding groups.';
};

sub query_params {
    return [
        {
            param => 'group',
            description => 'Filter for sound handles of a specific group',
            query => {
                first => sub {
                    my $q = shift;
                    { 'group.name' => $q };
                },
                second => sub {
                    return { join => 'group' };
                },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SoundHandles/;

sub resource_name{
    return 'soundhandles';
}

sub dispatch_path{
    return '/api/soundhandles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-soundhandles';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});



1;

# vim: set tabstop=4 expandtab:
