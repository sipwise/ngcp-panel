package NGCP::TestFramework;

use strict;
use warnings;
use Cpanel::JSON::XS;
use Data::Walk;
use List::Util qw(max);
use Moose;
use Net::Domain qw(hostfqdn);
use Test::More;
use threads;
use threads::shared;
use Thread::Queue;
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
    my $client = NGCP::TestFramework::Client->new( { uri => $base_uri, log_debug => 0 } );
    my $test_executor = NGCP::TestFramework::TestExecutor->new();

    # initializing time to add to fields which need to be unique
    my $retained :shared = shared_clone({ t => time });

    my @threads;
    my %queues;

    my $threads_no = max ( map { $_->{thread} || 0 } @$testing_data ); 

    for (0..$threads_no) {
        $queues{$_} = Thread::Queue->new();
    }

    foreach my $test ( @$testing_data ) {
        next if ( $test->{skip} );

        if ( $test->{thread} ) {
            $queues{$test->{thread}}->enqueue($test);
        }
        else {
            $queues{0}->enqueue($test);
        }
    }

    for (0..$threads_no) {
        $queues{$_}->end();
    }

    for (1..$threads_no) {
        push @threads, threads->create( {'context' => 'void'}, \&worker, $self, $base_uri, $request_builder, $client, $test_executor, $retained, $queues{$_} );
    }

    $self->worker($base_uri, $request_builder, $client, $test_executor, $retained, $queues{0});

    foreach ( @threads ){
      $_->join();
    }

    done_testing;
}

sub worker {
    my ( $self, $base_uri, $request_builder, $client, $test_executor, $retained, $tests_queue ) = @_;

    while ( my $test = $tests_queue->dequeue_nb() ) {
        next if ( $test->{skip} );

        lock( $retained );
        #check if variables are available
        cond_wait( $retained ) until $self->_variables_available( $retained, $test );
        # build request
        my $request = $request_builder->build({
            method  => $test->{method},
            path    => $test->{path},
            header  => $test->{header} || undef,
            content => $test->{content} || undef,
            retain  => $retained
        });

        # handle separate types
        if ( $test->{type} eq 'item' ) {
            my $result = $client->perform_request($request);
            if ( $test->{retain} ) {
                $self->_get_retained_elements( $test->{retain}, $retained, $result );
            }
            if ( $test->{operations} ) {
                $self->_perform_operations( $test->{operations}, $retained );
            }
            $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} ) if ( $test->{conditions} );
        }
        elsif ( $test->{type} eq 'batch' ) {
            foreach my $iteration ( 1..$test->{number} ) {
                my $result = $client->perform_request($request);
                if ( $test->{retain} ) {
                    $self->_get_retained_elements( $test->{retain}, $retained, $result );
                }
                if ( $test->{operations} ) {
                    $self->_perform_operations( $test->{operations}, $retained );
                }
                $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} ) if ( $test->{conditions} );
            }
        }
        elsif ( $test->{type} eq 'pagination' ) {
            my $nexturi = $test->{path};
            do {
                $request->uri( $base_uri.$nexturi );
                my $result = $client->perform_request($request);
                if ( $test->{retain} ) {
                    $self->_get_retained_elements( $test->{retain}, $retained, $result );
                }
                if ( $test->{operations} ) {
                    $self->_perform_operations( $test->{operations}, $retained );
                }
                my $body = decode_json( $result->decoded_content() );

                #build default conditions for pagination
                my $conditions = {
                    is => {
                        $nexturi => $body->{_links}->{self}->{href}
                    }
                };

                $test_executor->run_tests( $conditions, $result, $retained, $test->{name} ) if ( $conditions );

                if( $body->{_links}->{next}->{href} ) {
                    $nexturi = $body->{_links}->{next}->{href};
                } else {
                    $nexturi = undef;
                }
            } while ( $nexturi )
        }
    }
}

sub _get_retained_elements {
    my ( $self, $retain, $retained, $result ) = @_;

    while ( my ( $retain_elem, $retain_value ) = each %{$retain} ) {
        if ( $retain_value =~ /.+\..+/ ) {
            my @splitted_values = split (/\./, $retain_value);
            $retained->{$retain_elem} = shared_clone($self->_retrieve_from_composed_key( $result, \@splitted_values, $retain_elem ));
        }
        elsif ( $retain_value eq 'body' ) {
            $retained->{$retain_elem} = shared_clone(decode_json( $result->decoded_content() ));
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

sub _variables_available {
    my( $self, $retained, $test ) = @_;

    return 0 if ( $test->{path} =~ /\$\{(.*)\}/ && !$retained->{$1} );

    # substitute variables in content
    if ( $test->{content} && ref $test->{content} eq 'HASH' ) {
        foreach my $content_key (keys %{$test->{content}}) {
            return 0 if ( $test->{content}->{$content_key} =~ /\$\{(.*)\}/ && !$retained->{$1} );
        }
    }
    return 1;
}

sub _perform_operations {
    my ( $self, $operations, $retained ) = @_;

    foreach my $operation ( keys %$operations ) {
        foreach my $mapping ( @{$operations->{$operation}} ) {
            my ( $variable, $value ) = each %$mapping;
            $variable =~ /\$\{(.*)\}/;
            $variable = $retained->{$1};
            if ( $operation eq 'delete' ) {
                if ( $variable->{$value} ){
                    delete $variable->{$value};
                }
                else {
                    *delete_value = sub {
                        if ( ref $_ eq 'HASH' && $_->{$value} ) {
                            delete $_->{$value};
                        }
                    };
                    walkdepth {wanted => \&delete_value}, $variable;
                }
            }
        }
    }
}


1;
