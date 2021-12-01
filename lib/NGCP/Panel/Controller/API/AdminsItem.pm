package NGCP::Panel::Controller::API::AdminsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Admins/;

use NGCP::Panel::Utils::Auth;
use HTTP::Status qw(:constants);

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get
        handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller lintercept ccareadmin ccare/],
        Journal => [qw/admin reseller lintercept ccareadmin ccare/],
    }
});

sub PATCH :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, admin => $item);
        my $old_resource = { $item->get_inflated_columns };
        #use saltedpass so we have a password field for applying patch
        #we later check in update_item and if the password field is still
        #the same with saltedpass we don't update the password
        $old_resource->{password} = $old_resource->{salted_pass};

        # This trick allows to call apply_patch below without "role" reference error.
        $old_resource->{role} = undef;

        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;

        my $hal = $self->hal_from_item($c, $item);
        last unless $self->add_update_journal_item_hal($c,{ hal => $hal, id => $item->id });

        $guard->commit;

        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
    }
    return;
}

sub delete_item {
    my ($self, $c, $item) = @_;

    my $special_user_login = NGCP::Panel::Utils::Auth::get_special_admin_login();

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

sub resource_from_item{
    my($self, $c, $item) = @_;

    my $res;
    if ('HASH' eq ref $item) {
        $res = $item;
    } else {
        $res = { $item->get_inflated_columns };
    }

    my $role_id = delete $res->{role_id};
    if ($role_id) {
        $res->{role} = NGCP::Panel::Utils::UserRole::find_row_by_id($c, $role_id)->role;
    }

    return $res;
}

1;

# vim: set tabstop=4 expandtab:
