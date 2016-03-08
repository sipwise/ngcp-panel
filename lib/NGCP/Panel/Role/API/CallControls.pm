package NGCP::Panel::Role::API::CallControls;
use NGCP::Panel::Utils::Generic qw(:all);

use base 'NGCP::Panel::Role::API';


use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Form::CallControl::CallAPI;

sub item_rs {
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CallControl::CallAPI->new;
}

1;
# vim: set tabstop=4 expandtab:
