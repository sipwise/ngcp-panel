package NGCP::TestFramework;

use strict;
use warnings;
use JSON;
use Moose;
use Net::Domain qw(hostfqdn);
use Test::More;
use YAML::XS qw/LoadFile/;
use Data::Dumper;

use NGCP::TestFramework::RequestBuilder;
use NGCP::TestFramework::Client;
use NGCP::TestFramework::TestExecutor;

has 'file_path' => (
    isa => 'Str',
    is => 'ro'
);

sub run {
    my ( $self ) = @_;

    unless ( $self->file_path ) {
        return;
    }

    my $testing_data = LoadFile($self->file_path);

    my $base_uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
    my $request_builder = NGCP::TestFramework::RequestBuilder->new({ base_uri => $base_uri });
    my $client = NGCP::TestFramework::Client->new( { uri => $base_uri, log_debug => 1 } );
    my $test_executor = NGCP::TestFramework::TestExecutor->new();

    # initializing time to add to fields which need to be unique
    my $retained = { time => time };

    foreach my $test_no ( sort { $a <=> $b } keys %$testing_data ) {
        # build request
        my $request = $request_builder->build({
            method  => $testing_data->{$test_no}->{method},
            path    => $testing_data->{$test_no}->{path},
            header  => $testing_data->{$test_no}->{header} || undef,
            content => $testing_data->{$test_no}->{content} || undef,
            retain  => $retained
        });

        # handle separate types
        if ( $testing_data->{$test_no}->{type} eq 'item' ) {
            my $result = $client->perform_request($request);
            if ( $testing_data->{$test_no}->{retain} ) {
                $self->_get_retained_elements( $testing_data->{$test_no}->{retain}, $retained, $result );
            }
            $test_executor->run_tests( $testing_data->{$test_no}->{conditions}, $result, $retained ) if ( $testing_data->{$test_no}->{conditions} );
        }
        elsif ( $testing_data->{$test_no}->{type} eq 'collection' ) {
            foreach my $iteration ( 1..$testing_data->{$test_no}->{number} ) {
                my $result = $client->perform_request($request);
                if ( $testing_data->{$test_no}->{retain} ) {
                    $self->_get_retained_elements( $testing_data->{$test_no}->{retain}, $retained, $result );
                }
                $test_executor->run_tests( $testing_data->{$test_no}->{conditions}, $result, $retained ) if ( $testing_data->{$test_no}->{conditions} );
            }
        }
        if ( $testing_data->{$test_no}->{type} eq 'pagination' ) {
            my $nexturi = $testing_data->{$test_no}->{path};
            do {
                $request->uri( $base_uri.$nexturi );
                my $result = $client->perform_request($request);
                if ( $testing_data->{$test_no}->{retain} ) {
                    $self->_get_retained_elements( $testing_data->{$test_no}->{retain}, $retained, $result );
                }
                my $body = JSON::from_json( $result->decoded_content() );

                #build default conditions for pagination
                $testing_data->{$test_no}->{conditions} = {
                    is => {
                        $nexturi => $body->{_links}->{self}->{href}
                    }
                };

                $test_executor->run_tests( $testing_data->{$test_no}->{conditions}, $result, $retained ) if ( $testing_data->{$test_no}->{conditions} );
                delete $testing_data->{$test_no}->{conditions}->{is}->{$nexturi};

                if( $body->{_links}->{next}->{href} ) {
                    $nexturi = $body->{_links}->{next}->{href};
                } else {
                    $nexturi = undef;
                }
            } while ( $nexturi )
        }
    }
    done_testing;
}

sub _get_retained_elements {
    my ( $self, $retain, $retained, $result ) = @_;

    while ( my ( $retain_elem, $retain_value ) = each %{$retain} ) {
        if ( $retain_value =~ /.+\..+/ ) {
            my @splitted_values = split (/\./, $retain_value);
            $retained->{$retain_elem} = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retain_elem );
        }
        elsif ( $retain_value eq 'body' ) {
            $retained->{$retain_elem} = JSON::from_json( $result->decoded_content() );
        }
        else {
            return {
                success => 0,
                message => 'Wrong retain instructions!'
            }
        }
    }
}

sub _retrieve_from_composed_key {
    my ( $self, $result, $splitted_values, $retain_elem ) = @_;

    if ( $splitted_values->[0] eq 'header' ) {
        my $value = $result->header(ucfirst $splitted_values->[1]);
        if ( $retain_elem =~ /^.+_id$/ ) {
            $value =~ /^.+\/(\d+)$/;
            $value = $1;
        }
        return $value;
    }
}

1;
