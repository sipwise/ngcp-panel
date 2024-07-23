package NGCP::Panel::Controller::API::SMSItem;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SMS/;

use HTTP::Status qw(:constants);


__PACKAGE__->set_config({
    required_licenses => [qw/sms/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

1;

# vim: set tabstop=4 expandtab:
