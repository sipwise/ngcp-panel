package NGCP::Panel::Controller::API::VoicemailGreetings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/OPTIONS/];
}

sub api_description {
    return 'Defines the voicemail greetings. A GET on an item with Accept "audio/x-wav" returns the binary blob of the greeting.';
};

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::VoicemailGreetings/;


1;

# vim: set tabstop=4 expandtab:
