package NGCP::Panel::Authentication::Store::RoleFromRealm;
use Sipwise::Base;
use parent 'Catalyst::Authentication::Store::DBIx::Class::User';

sub roles {
    my ($self) = @_;

    if ($self->auth_realm) {
        for my $auth_type (qw/admin_bcrypt admin api_admin_cert api_admin_http/) {
            if ($auth_type eq $self->auth_realm) {
                $self->_user->is_superuser ? return "admin"
                                           : return "reseller";
            }
        }
        foreach my $auth_type (qw/subscriber api_subscriber_http api_subscriber_jwt/) { # TODO: simplify this
            if ($auth_type eq $self->auth_realm) {
                $self->_user->admin ? return "subscriberadmin"
                                    : return "subscriber";
            }
        }
    }
    return "invalid";
}
1;
# vim: set tabstop=4 expandtab:
