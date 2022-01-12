package NGCP::Panel::Utils::UserRole;

use Sipwise::Base;
use Scalar::Util qw(blessed);

sub _flags_to_name {
    my $params = shift;
    return unless $params && ref $params;

    my %flags;
    if (blessed($params)) { # object
        map { $flags{$_} = $params->$_ }
            qw(is_system is_superuser is_ccare lawful_intercept);
    } else {
        %flags = %{$params};
    }

    # "system" - is_system = 1,
    # "admin" - is_superuser = 1
    # "reseller" - is_superuser = 0
    # "ccareadmin" - is_ccare = 1, is_superuser = 1
    # "ccare" = is_ccare = 1, is_superuser = 0
    # "lawful_intercept" - lintercept = 1

    if ($flags{is_system}) {
        return 'system';
    }

    if ($flags{lawful_intercept}) {
        return 'lintercept'
    }

    if ($flags{is_superuser}) {
        if ($flags{is_ccare}) {
            return 'ccareadmin';
        }
        return 'admin';
    }

    if ($flags{is_ccare}) {
        return 'ccare';
    }

    return 'reseller';
}

sub name_to_flags {
    my $name = shift;

    my @flag_names = qw/ is_system is_superuser is_ccare lawful_intercept /;
    my %map = (
        system     => [1, 0, 0, 0],
        admin      => [0, 1, 0, 0],
        reseller   => [0, 0, 0, 0],
        ccareadmin => [0, 1, 1, 0],
        ccare      => [0, 0, 1, 0],
        lintercept => [0, 0, 0, 1],
    );

    return $map{$name} ?
        ( map { $flag_names[$_] => $map{$name}->[$_] } 0..$#flag_names ) :
        ();
}

sub resolve_role_id {
    my ($c, $params) = @_;

    my $role_name = _flags_to_name($params) // return;
    my $role = &find_row_by_name($c, $role_name);

    return $role ? $role->id : undef;
}

sub resolve_flags {
    my ($c, $role_id) = @_;

    my $role_name = $c->model('DB')->resultset('acl_roles')->search({id => $role_id})->first->role
        || return ();

    return &name_to_flags($role_name);
}

sub find_row_by_name {
    my ($c, $name) = @_;

    return $c->model('DB')->resultset('acl_roles')->find({role => $name});
}

sub find_row_by_id {
    my ($c, $id) = @_;

    return $c->model('DB')->resultset('acl_roles')->find($id);
}

sub resolve_resource_role {
    my ($c, $resource) = @_;

    my $role_name = delete $resource->{role};
    if ($role_name) {
        $resource = { %$resource, &name_to_flags($role_name) };
        $resource->{role_id} = &find_row_by_name($c, $role_name)->id;
    } else {
        $resource->{role_id} = &resolve_role_id($c, $resource);
    }

    return $resource;
}

sub has_permission {
    my ($c, $own_role_id, $to_role_id) = @_;
    return 1 if $own_role_id == -1; # NGCP::API::Client user
    return 0 unless $own_role_id && $to_role_id;

    return $c->model('DB')->resultset('acl_role_mappings')->search({
        accessor_id => $own_role_id,
        has_access_to_id => $to_role_id,
    })->count() ? 1 : 0;
}

1;
