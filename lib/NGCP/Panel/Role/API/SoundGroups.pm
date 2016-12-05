package NGCP::Panel::Role::API::SoundGroups;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use HTTP::Status qw(:constants);

sub item_name {
    return 'soundgroups';
}

sub resource_name{
    return 'soundgroups';
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_sound_groups');
    return $item_rs;
}

1;
# vim: set tabstop=4 expandtab:
