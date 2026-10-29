package NGCP::Panel::Controller::API::CountriesItem;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Countries/;

use Sipwise::Base;


use HTTP::Status qw(:constants);


__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

1;

# vim: set tabstop=4 expandtab:
