package NGCP::Panel::Controller::API::AdminsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Admins/;

use NGCP::Panel::Utils::Admin;

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

__PACKAGE__->config(
    action => {
        (map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }),
        @{ __PACKAGE__->get_journal_action_config(__PACKAGE__->resource_name,{
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Does => [qw(ACL RequireSSL)],
        }) },
    },
);

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $admin = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, admin => $admin);

        $c->log->error("++++++ trying to delete admin #$id as #" . $c->user->id);
        
        my $special_user_login = NGCP::Panel::Utils::Admin::get_special_admin_login();
        if($admin->login eq $special_user_login) {
            $self->error($c, HTTP_FORBIDDEN, "Cannot delete special user '$special_user_login'");
            last;
        }
        if($c->user->id == $id) {
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
            return $self->hal_from_item($c,$admin); });
        
        $admin->delete;

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
