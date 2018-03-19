package NGCP::Panel::Controller::API::PhonebookEntriesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PhonebookEntries/;

use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    my $rs = $self->_item_rs($c,$resource);#maybe copy-paste it here?
    return unless $rs;
    $item->update($resource);
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
