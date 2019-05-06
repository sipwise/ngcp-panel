package NGCP::TestFramework::TestExecutor;

use strict;
use warnings;
use JSON;
use Moose;
use Test::More;
use Data::Dumper;

sub run_tests {
    my ( $self, $conditions, $result, $retained ) = @_;

    foreach my $condition ( keys %$conditions ) {
        if ( $condition eq 'is' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param =~ /.+\..+/ ) {
                    my @splitted_values = split (/\./, $check_param);
                    my $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                    is ($check_value, $conditions->{$condition}->{$check_param},"check code in $check_param");
                }
                elsif ( $check_param eq 'code' ) {
                    is ($result->code, $conditions->{$condition}->{$check_param},"check code");
                }
                elsif ( $check_param eq 'header' ) {
                    foreach my $header_condition ( keys %{$conditions->{$condition}->{$check_param}} ) {
                        is ($result->header($header_condition), $conditions->{$condition}->{$check_param}->{$header_condition},"check header");
                    }
                }
                else {
                    is ($check_param, $conditions->{$condition}->{$check_param},"check for $check_param");
                }
            }
        }
        elsif ( $condition eq 'ok' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param eq 'options' ) {
                    my $body = JSON::from_json($result->decoded_content);
                    my @hopts = split /\s*,\s*/, $result->header('Allow');
                    ok(exists $body->{methods} && ref $body->{methods} eq "ARRAY", "check for valid 'methods' in body");
                    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
                        ok(grep { /^$opt$/ } @hopts, "check for existence of '$opt' in Allow header");
                        ok(grep { /^$opt$/ } @{ $body->{methods} }, "check for existence of '$opt' in body");
                    }
                }
            }
        }
        elsif ( $condition eq 'like' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param =~ /.+\..+/ ) {
                    my @splitted_values = split (/\./, $check_param);
                    my $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                    like ($check_value, qr/$conditions->{$condition}->{$check_param}/,"check code in $check_param");
                }
            }
        }
    }
}

sub _retrieve_from_composed_key {
    my ( $self, $result, $splitted_values, $retained ) = @_;

    if ( $splitted_values->[0] eq 'body' ) {
        my $body = JSON::from_json($result->decoded_content);
        return $body->{$splitted_values->[1]};
    }
    elsif ( $splitted_values->[0] =~ /\$\{(.*)\}/ ) {
        my $value = $retained->{$1};
        grep { $value = $value->{$splitted_values->[$_]} } (1..(scalar @$splitted_values - 1));
        return $value;
    }
}

1;
