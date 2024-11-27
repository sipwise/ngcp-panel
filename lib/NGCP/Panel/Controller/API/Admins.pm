package NGCP::Panel::Controller::API::Admins;
use NGCP::Panel::Utils::Generic qw(:all);
use NGCP::Panel::Utils::UserRole;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Admins/;

use HTTP::Status qw(:constants);

sub api_description {
    return 'Defines admins to log into the system via panel or api.';
}

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccare ccareadmin lintercept/],
});

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for admins belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'login',
            description => 'Filter for admins with a specific login', # (wildcards possible)',
            query_type => 'wildcard',
        },
    ];
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    if ($c->user->roles eq 'lintercept') {
        $self->error($c, HTTP_FORBIDDEN, "Cannot create admin users");
        return;
    }
    unless($c->user->is_master) {
        $self->error($c, HTTP_FORBIDDEN, "Cannot create admin without master permissions");
        return;
    }

    $resource = NGCP::Panel::Utils::UserRole::resolve_resource_role($c, $resource);
    unless (defined $resource->{role_id} &&
            NGCP::Panel::Utils::UserRole::has_permission(
                $c, $c->user->acl_role->id, $resource->{role_id})) {
        $self->error($c, HTTP_FORBIDDEN, "Cannot create admin user");
        return;
    }

    my $item;
    try {
        my $pass = delete $resource->{password};
        $resource->{auth_mode} ||= 'local';
        $item = $c->model('DB')->resultset('admins')->create($resource);
        NGCP::Panel::Utils::Admin::insert_password_journal(
            $c, $item, $pass
        );

    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create admin.", $e);
        return;
    }

    return $item;
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
