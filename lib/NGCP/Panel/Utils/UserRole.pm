package NGCP::Panel::Utils::UserRole;

use Sipwise::Base;

sub _flags_to_name {
    my (%flags) = @_;

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


sub resolve_role_id {
    my ($c, $params) = @_;

    my $role_name = &_flags_to_name(%$params);
    my $role = $c->model('DB')->resultset('acl_roles')->search({role => $role_name})->first;

    return $role->id;
}

1;