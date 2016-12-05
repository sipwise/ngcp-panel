package NGCP::Panel::Controller::API::SoundGroups;


use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SoundGroups/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Security;

__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines banned users.';
}

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for sound groups with a specific name',
            query_type => 'string_like',
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
