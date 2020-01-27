package TestFramework::RequestBuilder;

use strict;
use warnings;
use HTTP::Request;
use Cpanel::JSON::XS;
use Log::Log4perl qw(:easy);
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
        $args->{content} = $self->_replace_vars_recursion($args->{content}, $args->{retain});
    }
}

sub _replace_vars_recursion {
    my ( $self, $elem, $retain ) = @_;

    if ( ref $elem eq 'HASH' ) {
        foreach my $k (keys %{$elem}) {
            $elem->{$k} = $self->_replace_vars_recursion($elem->{$k}, $retain);
        }
    } elsif ( ref $elem eq 'ARRAY' ) {
        foreach my $e ( @{$elem} ) {
            $e = $self->_replace_vars_recursion($e, $retain);
        }
    } elsif ( ref $elem eq '' and defined $elem and $elem =~ /\$\{(.*)\}/ ) {
        if ( ref $retain->{$1} eq '' ) {
            $elem =~ s/\$\{(.*)\}/$retain->{$1}/;
        } else {
            $elem = $retain->{$1};
        }
    }

    return $elem;
}

1;
