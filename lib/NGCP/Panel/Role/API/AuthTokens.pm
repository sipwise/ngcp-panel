package NGCP::Panel::Role::API::AuthTokens;

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::AuthToken", $c);
}

1;
# vim: set tabstop=4 expandtab:
