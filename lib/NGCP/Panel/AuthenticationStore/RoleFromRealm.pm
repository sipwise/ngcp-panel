package NGCP::Panel::AuthenticationStore::RoleFromRealm;
use Sipwise::Base;
extends 'Catalyst::Authentication::Store::DBIx::Class::User';

sub roles {
    my ($self) = @_;

    given($self->auth_realm) {
        when([qw/admin api_admin_cert api_admin_http/]) {
            if($self->_user->is_superuser) {
                return "admin";
            } else {
                return "reseller";
            }
        }
        when([qw/subscriber api_subscriber/]) {
            if($self->_user->admin) {
                return "subscriberadmin";
            } else {
                return "subscriber";
            }
        }
        default {
            return "invalid";
        }
    }
}
# vim: set tabstop=4 expandtab:
