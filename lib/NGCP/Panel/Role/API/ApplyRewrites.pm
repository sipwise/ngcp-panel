package NGCP::Panel::Role::API::ApplyRewrites;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Form::RewriteRule::ApplyAPI;

sub _item_rs {
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::RewriteRule::ApplyAPI->new;
}

1;
# vim: set tabstop=4 expandtab:
