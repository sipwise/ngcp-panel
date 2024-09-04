package NGCP::Panel::Role::API::PasswordChange;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);


sub _item_rs {
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::PasswordChangeAPI", $c);
}

1;
# vim: set tabstop=4 expandtab:
