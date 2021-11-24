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

sub _name_to_flags {
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
        undef;
}

sub resolve_role_id {
    my ($c, $params) = @_;

    my $role_name = _flags_to_name($params) // return;
    my $role = $c->model('DB')->resultset('acl_roles')->find({role => $role_name});

    return $role ? $role->id : undef;
}

sub resolve_flags {
    my ($c, $role_id) = @_;

    my $role_name = $c->model('DB')->resultset('acl_roles')->search({id => $role_id})->first->role
        || return ();

    return &_name_to_flags($role_name);
}

1;
