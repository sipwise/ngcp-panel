package NGCP::TestFramework::TestExecutor;

use strict;
use warnings;
use Cpanel::JSON::XS;
use Data::Walk;
use Moose;
use Test::More;
use Data::Dumper;

sub run_tests {
    my ( $self, $conditions, $result, $retained, $test_name ) = @_;

    foreach my $condition ( keys %$conditions ) {
        if ( $condition eq 'is' ) {
            while ( my ( $check_param, $check_value ) = each %{$conditions->{$condition}} ) {
                if ( $check_value =~ /^\$\{(.*)\}$/ ) {
                    $check_value = $retained->{$1};
                }
                if ( $check_param =~ /^\$\{(.*)\}$/ ) {
                    $check_param = $retained->{$1};
                }
                if ( $check_param =~ /.+\..+/ ) {
                    my @splitted_values = split (/\./, $check_param);
                    $check_param = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                    is ($check_param, $check_value, $test_name);
                }
                elsif ( $check_param eq 'code' ) {
                    is ($result->code, $check_value, $test_name);
                }
                elsif ( $check_param eq 'header' ) {
                    foreach my $header_condition ( keys %{$conditions->{$condition}->{$check_param}} ) {
                        is ($result->header($header_condition), $check_value->{$header_condition}, $test_name);
                    }
                }
                else {
                    is ($check_param, $check_value, $test_name);
                }
            }
        }
        elsif ( $condition eq 'ok' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param eq 'options' ) {
                    my $body = decode_json($result->decoded_content);
                    my @hopts = split /\s*,\s*/, $result->header('Allow');
                    ok(exists $body->{methods} && ref $body->{methods} eq "ARRAY", $test_name);
                    foreach my $opt(@{$conditions->{$condition}->{$check_param}}) {
                        ok(grep { /^$opt$/ } @hopts, $test_name);
                        ok(grep { /^$opt$/ } @{ $body->{methods} }, $test_name);
                    }
                }
                if ( $conditions->{$condition}->{$check_param} eq 'defined' || $conditions->{$condition}->{$check_param} eq 'undefined') {
                    if ( $check_param =~ /.+\..+/ ) {
                        my @splitted_values = split (/\./, $check_param);
                        my $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                        $conditions->{$condition}->{$check_param} eq 'defined' ?
                            ok(defined $check_value, $test_name) : ok(!defined $check_value, $test_name);
                    }
                }
            }
        }
        elsif ( $condition eq 'like' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param =~ /.+\..+/ ) {
                    my @splitted_values = split (/\./, $check_param);
                    my $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                    like ($check_value, qr/$conditions->{$condition}->{$check_param}/, $test_name);
                }
            }
        }
        elsif ( $condition eq 'is_deeply' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                *replace_variables = sub {
                    if ( ref $_ eq 'HASH' ) {
                        while ( my ( $key, $value ) = each %$_ ) {
                            if ( $value && $value =~ /\$\{(.*)\}/ ) {
                                $_->{$key} = $retained->{$1};
                            }
                        }
                    }
                };

                walkdepth {wanted => \&replace_variables}, $conditions->{$condition}->{$check_param};
                if ( $conditions->{$condition}->{$check_param} =~ /^\$\{(.*)\}$/ ) {
                    $conditions->{$condition}->{$check_param} = $retained->{$1};
                }
                my $check_value;
                if ( $check_param=~ /^\$\{(.*)\}$/ ) {
                    $check_value = $retained->{$1};
                }
                if ( $check_param =~ /.+\..+/ ) {
                    my @splitted_values = split (/\./, $check_param);
                    $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                }
                is_deeply ($check_value, $conditions->{$condition}->{$check_param}, $test_name);
            }
        }
    }
}

sub _retrieve_from_composed_key {
    my ( $self, $result, $splitted_values, $retained ) = @_;

    if ( $splitted_values->[0] eq 'body' ) {
        my $body = decode_json($result->decoded_content);
        return $body->{$splitted_values->[1]};
    }
    elsif ( $splitted_values->[0] =~ /\$\{(.*)\}/ ) {
        my $value = $retained->{$1};
        grep { $value = $value->{$splitted_values->[$_]} } (1..(scalar @$splitted_values - 1));
        return $value;
    }
}

1;
