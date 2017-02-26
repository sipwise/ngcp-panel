package NGCP::Panel::Role::API::CallControls;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Form::CallControl::CallAPI;

sub _item_rs {
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CallControl::CallAPI->new;
}

1;
# vim: set tabstop=4 expandtab:
