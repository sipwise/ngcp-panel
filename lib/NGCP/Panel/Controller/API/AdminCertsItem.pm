package NGCP::Panel::Controller::API::AdminCertsItem;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::AdminCerts/;

use Sipwise::Base;

use HTTP::Status qw(:constants);


__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub delete_item {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;

    if (
        $item->id != $c->user->id &&
        (
            !$c->user->is_master ||
            !NGCP::Panel::Utils::UserRole::has_permission($c, $c->user->acl_role->id, $item->acl_role->id)
        )
    ){
        $self->error($c, HTTP_FORBIDDEN, 'Cannot delete certificate');
        return;
    }

    try {
        $item->update({
            ssl_client_m_serial => undef,
            ssl_client_certificate => undef,
        });
    } catch($e) {
        $c->log->error("failed to delete administrator certificate: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to delete administrator certificate.");
        return;
    }

    return 1;
}

1;

# vim: set tabstop=4 expandtab:
