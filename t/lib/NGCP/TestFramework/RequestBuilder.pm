package NGCP::TestFramework::RequestBuilder;

use strict;
use warnings;
use HTTP::Request;
use Cpanel::JSON::XS;
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
    $req->content( encode_json( $args->{content} ) ) if $args->{content};

    return $req;
}

sub _replace_vars {
    my ( $self, $args ) = @_;

    # substitute variables in path
    if ( $args->{path} =~ /\$\{(.*)\}/ ) {
        $args->{path} =~ s/\$\{(.*)\}/$args->{retain}->{$1}/;
    }

    # substitute variables in content
    if ( $args->{content} ) {
        if ( ref $args->{content} eq 'HASH' ) {
            foreach my $content_key (keys %{$args->{content}}) {
                if ( $args->{content}->{$content_key} =~ /\$\{(.*)\}/ ) {
                    $args->{content}->{$content_key} =~ s/\$\{(.*)\}/$args->{retain}->{$1}/;
                }
            }
        }
        else {
            if ( $args->{content} =~ /\$\{(.*)\}/ ) {
                $args->{content} = $args->{retain}->{$1};
            }
        }
    }
}

1;
