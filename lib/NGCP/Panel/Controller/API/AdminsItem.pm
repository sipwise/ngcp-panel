package NGCP::Panel::Controller::API::AdminsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Admins/;

use NGCP::Panel::Utils::Admin;
use HTTP::Status qw(:constants);

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}   

__PACKAGE__->set_config();

sub delete_item {
    my ($self, $c, $item) = @_;

    my $special_user_login = NGCP::Panel::Utils::Admin::get_special_admin_login();

    if($item->login eq $special_user_login) {
        $self->error($c, HTTP_FORBIDDEN, "Cannot delete special user '$special_user_login'");
        last;
    }
    if($c->user->id == $item->id) {
        $self->error($c, HTTP_FORBIDDEN, "Cannot delete own user");
        last;
    }
    if($c->user->read_only) {
        $self->error($c, HTTP_FORBIDDEN, "Insufficient permissions");
        last;
    }

    # reseller association is checked in item_rs of role

    last unless $self->add_delete_journal_item_hal($c,sub {
        my $self = shift;
        my ($c) = @_;
        return $self->hal_from_item($c, $item); });
    
    $item->delete;
    return 1;
}

#we don't use update_item for the admins now, as we dont allo PUT and PATCH
sub update_item_model {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    if($old_resource->{login} eq NGCP::Panel::Utils::Admin::get_special_admin_login()) {
        my $active = $resource->{is_active};
        $resource = $old_resource;
        $resource->{is_active} = $active;
    }
    $item->update($resource);
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
