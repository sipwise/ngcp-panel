package Catalyst::Plugin::NGCP::RealmCookie;
use Moose;
use namespace::autoclean;
extends 'Catalyst::Plugin::Session::State::Cookie';

# prevents creation of an empty ..._session cookies during
# session pre-setup
sub setup_session {
    my $c = shift;

    $c->maybe::next::method(@_);

    return;
}

sub get_cookie_name {
    my $c = shift;
    my $ngcp_api_realm = $c->request->env->{NGCP_REALM} // "";

    my $cookie_name = $c->_session_plugin_config->{cookie_name} //
                        Catalyst::Utils::appprefix($c);
    $cookie_name .= $ngcp_api_realm ? '_'.$ngcp_api_realm : '';
    return $cookie_name;
}

sub update_session_cookie {
    my ( $c, $updated ) = @_;

    unless ( $c->cookie_is_rejecting( $updated ) ) {
        my $cookie_name = $c->get_cookie_name;
        $c->response->cookies->{$cookie_name} = $updated;
    }
}

sub get_session_cookie {
    my $c = shift;

    my $cookie_name = $c->get_cookie_name;

    return $c->request->cookies->{$cookie_name};
}

1;
