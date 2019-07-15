package NGCP::TestFramework::TestExecutor;

use strict;
use warnings;
use Cpanel::JSON::XS;
use Data::Walk;
use Log::Log4perl qw(:easy);
use Moose;
use Test::More;
use Data::Dumper;

Test::More->builder->output ('/var/log/ngcp/test-framework/result.txt');
Test::More->builder->failure_output ('/var/log/ngcp/test-framework/errors.txt');

sub run_tests {
    my ( $self, $conditions, $result, $retained, $test_name ) = @_;

    my $tests_result = { success => 1 };
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
                    DEBUG ( "Checking is for $check_param and $check_value" );
                    if ( is ($check_param, $check_value, $test_name) ) {
                        INFO ( "Check ok." );
                    }
                    else {
                        ERROR ( "NOT OK. Expected: $check_param. Got: $check_value" );
                        $tests_result->{success} = 0;
                        push @{$tests_result->{errors}}, "Error at 'is' condition for test '$test_name'";
                    }
                }
                elsif ( $check_param eq 'code' ) {
                    DEBUG ( "Checking is for ".$result->code." and $check_value" );
                    if ( is ($result->code, $check_value, $test_name) ) {
                        INFO ( "Check ok." );
                    }
                    else {
                        ERROR ( "NOT OK. Expected: ".$result->code.". Got: $check_value" );
                        $tests_result->{success} = 0;
                        push @{$tests_result->{errors}}, "Error at 'is' condition for test '$test_name'";
                    }
                }
                elsif ( $check_param eq 'header' ) {
                    foreach my $header_condition ( keys %{$conditions->{$condition}->{$check_param}} ) {
                        DEBUG ( "Checking is for ".$result->header($header_condition)."and ".$check_value );
                        if ( is ($result->header($header_condition), $check_value->{$header_condition}, $test_name) ) {
                            INFO ( "Check ok." );
                        }
                        else{
                            ERROR ( "NOT OK. Expected: ".$result->header($header_condition).". Got: ".$check_value->{$header_condition} );
                            $tests_result->{success} = 0;
                            push @{$tests_result->{errors}}, "Error at 'is' condition for test '$test_name'";
                        }
                    }
                }
                else {
                    DEBUG ( "Checking is for $check_param and $check_value" );
                    if ( is ($check_param, $check_value, $test_name) ) {
                        INFO ( "Check ok." );
                    }
                    else {
                        ERROR ( "NOT OK. Expected: ".$check_param.". Got: ".$check_value );
                        $tests_result->{success} = 0;
                        push @{$tests_result->{errors}}, "Error at 'is' condition for test '$test_name'";
                    }
                }
            }
        }
        elsif ( $condition eq 'ok' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param eq 'options' ) {
                    my $body = decode_json($result->decoded_content);
                    my @hopts = split /\s*,\s*/, $result->header('Allow');
                    DEBUG ( "Checking ok for options" );
                    if ( ok(exists $body->{methods} && ref $body->{methods} eq "ARRAY", $test_name) ) {
                        INFO ( "Check ok." );
                    }
                    else {
                        ERROR ( "NOT OK. Check failed for existence of methods in body and reference of \$body->{methods} is ARRAY");
                        $tests_result->{success} = 0;
                        push @{$tests_result->{errors}}, "Error at 'ok' condition for test '$test_name'";
                    }
                    foreach my $opt(@{$conditions->{$condition}->{$check_param}}) {
                        if ( ok(grep { /^$opt$/ } @hopts, $test_name) ) {
                            INFO ( "Check ok." );
                        }
                        else {
                            ERROR ( "NOT OK. Check failed for existence of ".$opt." in header methods" );
                            $tests_result->{success} = 0;
                            push @{$tests_result->{errors}}, "Error at 'ok' condition for test '$test_name'";
                        }
                        if ( ok(grep { /^$opt$/ } @{ $body->{methods} }, $test_name) ) {
                            INFO ( "Check ok." );
                        }
                        else {
                            ERROR ( "NOT OK. Check failed for existence of ".$opt." in body methods" );
                            $tests_result->{success} = 0;
                            push @{$tests_result->{errors}}, "Error at 'ok' condition for test '$test_name'";
                        }
                    }
                }
                if ( $conditions->{$condition}->{$check_param} eq 'defined' || $conditions->{$condition}->{$check_param} eq 'undefined') {
                    if ( $check_param =~ /.+\..+/ ) {
                        my @splitted_values = split (/\./, $check_param);
                        my $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                        if ( $conditions->{$condition}->{$check_param} eq 'defined' ) {
                            DEBUG ( "Checking ok for defined" );
                            if ( ok(defined $check_value, $test_name) ) {
                                INFO ( "Check ok." );
                            }
                            else {
                                ERROR ( "NOT OK. Check failed for existence of ".$check_param );
                                $tests_result->{success} = 0;
                                push @{$tests_result->{errors}}, "Error at 'ok' condition for test '$test_name'";
                            }
                        }
                        else {
                            DEBUG ( "Checking ok for undefined" );
                            if ( ok(!defined $check_value, $test_name) ) {
                                INFO ( "Check ok." );
                            }
                            else {
                                ERROR ( "NOT OK. Check failed for non-existence of ".$check_param );
                                $tests_result->{success} = 0;
                                push @{$tests_result->{errors}}, "Error at 'ok' condition for test '$test_name'";
                            }
                        }
                    }
                }
            }
        }
        elsif ( $condition eq 'like' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                if ( $check_param =~ /.+\..+/ ) {
                    my @splitted_values = split (/\./, $check_param);
                    my $check_value = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retained );
                    DEBUG ( "Checking like for ".$check_value." against ".$conditions->{$condition}->{$check_param} );
                    if ( like ($check_value, qr/$conditions->{$condition}->{$check_param}/, $test_name) ) {
                        INFO ( "Check ok." );
                    }
                    else{
                        ERROR ( "NOT OK. Expected: ".$check_value." to be like: ".$conditions->{$condition}->{$check_param} );
                        $tests_result->{success} = 0;
                        push @{$tests_result->{errors}}, "Error at 'like' condition for test '$test_name'";
                    }
                }
            }
        }
        elsif ( $condition eq 'is_deeply' ) {
            foreach my $check_param (keys %{$conditions->{$condition}}) {
                local *replace_variables = sub {
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
                DEBUG ( "Checking is_deeply for: ".(Dumper $check_value)." and ".(Dumper $conditions->{$condition}->{$check_param}) );
                if ( is_deeply ($check_value, $conditions->{$condition}->{$check_param}, $test_name) ) {
                    INFO ( "Check ok." );
                }
                else{
                    ERROR ( "NOT OK. Expected:\n".$check_value."\n. Got:\n".$conditions->{$condition}->{$check_param} );
                    $tests_result->{success} = 0;
                    push @{$tests_result->{errors}}, "Error at 'is_deeply' condition for test '$test_name'";
                }
            }
        }
    }
    return $tests_result;
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
