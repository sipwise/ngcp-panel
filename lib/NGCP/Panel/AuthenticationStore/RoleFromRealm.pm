package NGCP::Panel::AuthenticationStore::RoleFromRealm;
use Sipwise::Base;
extends 'Catalyst::Authentication::Store::DBIx::Class::User';

sub roles {
    my ($self) = @_;
    return $self->auth_realm;
}
