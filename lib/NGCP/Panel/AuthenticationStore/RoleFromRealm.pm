package NGCP::Panel::AuthenticationStore::RoleFromRealm;
use Sipwise::Base;
extends 'Catalyst::Authentication::Store::DBIx::Class::User';

sub roles {
    my ($self) = @_;

    if($self->auth_realm eq "subscriber" && $self->_user->admin) {
    	return "subscriberadmin";
    }
    return $self->auth_realm;
}
