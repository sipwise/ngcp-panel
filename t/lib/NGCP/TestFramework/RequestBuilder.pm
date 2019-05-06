package NGCP::TestFramework::RequestBuilder;

use strict;
use warnings;
use HTTP::Request;
use JSON;
use Moose;
use Data::Dumper;

has 'base_uri' => (
    isa => 'Str',
    is => 'ro'
);

sub build {
    my ( $self, $args ) = @_;

    my @methods = ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'HEAD', 'CONNECT', 'TRACE'];

    if ( !$args->{method} && !grep { $_ eq $args->{method} } @methods ) {
        return {
            success => 0,
            message => 'HTTP method missing or incorrect!'
        };
    }

    if ( !$args->{path} ) {
        return {
            success => 0,
            message => 'Path missing!'
        };
    }

    $self->_replace_vars($args);

    my $req = HTTP::Request->new( $args->{method}, $self->base_uri.$args->{path} );
    grep { $req->header( $_ => $args->{header}->{$_} ) } keys %{$args->{header}} if $args->{header};
    $req->content( JSON::to_json( $args->{content} ) ) if $args->{content};

    return $req;
}

sub _replace_vars {
    my ( $self, $args ) = @_;

    # substitute variables in path
    $args->{path} =~ s/\$\{(.*)\}/$args->{retain}->{$1}/;

    # substitute variables in content
    foreach my $content_key (keys %{$args->{content}}) {
        $args->{content}->{$content_key} =~ s/\$\{(.*)\}/$args->{retain}->{$1}/;
    }
}

1;
