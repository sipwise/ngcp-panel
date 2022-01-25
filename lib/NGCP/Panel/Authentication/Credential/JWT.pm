package NGCP::Panel::Authentication::Credential::JWT;
use warnings;
use strict;
use base "Class::Accessor::Fast";

__PACKAGE__->mk_accessors(qw/
    debug
    username_jwt
    username_field
    id_jwt
    id_field
    jwt_key
    alg
/);

use Crypt::JWT qw/decode_jwt/;
use TryCatch;
use Catalyst::Exception ();

sub new {
    my ( $class, $config, $c, $realm ) = @_;
    my $self = {
                # defaults:
                username_jwt => 'username',
                username_field => 'username',
                id_jwt => 'id',
                id_field => 'id',
                alg => 'HS256',
                #
                %{ $config },
                %{ $realm->{config} },  # additional info, actually unused
               };
    bless $self, $class;

    return $self;
}

sub authenticate {
    my ( $self, $c, $realm, $authinfo ) = @_;

    $c->log->debug("CredentialJWT::authenticate() called from " . $c->request->uri) if $self->debug;

    my $token;
    if ($c->req->uri->path =~ /^\/login_jwt$/) {
        $c->log->debug("Obtain token from the body") if $self->debug;
        $token = $c->req->body_data->{jwt} // return;
    } else {
        $c->log->debug("Obtain token from the header") if $self->debug;
        my $auth_header = $c->req->header('Authorization');
        return unless $auth_header;

        ($token) = $auth_header =~ m/Bearer\s+(.*)/;
        return unless $token;
    }

    $c->log->debug("Found token: $token") if $self->debug;

    my $jwt_data;
    try {
        $jwt_data = decode_jwt(token=>$token, key=>$self->jwt_key, accepted_alg => $self->alg);
        if ($jwt_data->{$self->id_field} && $jwt_data->{$self->id_field} eq 'uuid') {
            $c->log->debug('decoded subscriber JWT token');
        } else {
            $c->log->debug('decoded admin JWT token');
        }
    } catch ($e) {
        # something happened
        $c->log->debug("Error decoding token: $e") if $self->debug;
        return;
    }

    my $user_data = {
        %{ $authinfo // {} },
            $self->username_field => $jwt_data->{$self->username_jwt},
            $self->id_field => $jwt_data->{$self->id_jwt},
    };
    my $user_obj = $realm->find_user($user_data, $c);
    if (ref $user_obj) {
        return $user_obj;
    } else {
        $c->log->debug("Failed to find_user") if $self->debug;
        return;
    }
}

1;

__END__

=head1 NAME

NGCP::Panel::Authentication::Credential::JWT

=head1 DESCRIPTION

This authentication credential checker tries to read a JSON Web Token (JWT)
from the current request, verifies its signature and looks up the user
in the configured authentication store.

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Gerhard Jungwirth C<< <gjungwirth@sipwise.com> >>

