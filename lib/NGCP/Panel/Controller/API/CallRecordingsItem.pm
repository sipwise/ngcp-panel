package NGCP::Panel::Controller::API::CallRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallRecordings/;

use NGCP::Panel::Utils::Subscriber;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub delete_item {
    my ($self, $c, $item) = @_;
    NGCP::Panel::Utils::Subscriber::delete_callrecording( c => $c, recording => $item );
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
