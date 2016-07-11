package NGCP::Panel::Role::API::PbxDeviceModelImages;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

sub get_form {
    my ($self, $c) = @_;
    return;
}

1;
# vim: set tabstop=4 expandtab:
