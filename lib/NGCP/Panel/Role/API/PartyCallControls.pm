package NGCP::Panel::Role::API::PartyCallControls;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Form::PartyCallControl::API;

sub _item_rs {
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::PartyCallControl::API->new;
}

1;
# vim: set tabstop=4 expandtab:
