package NGCP::API::TestFramework;

use strict;
use warnings;
use Cpanel::JSON::XS;
use Data::Walk;
use DateTime qw();
use DateTime::Format::Strptime qw();
use DateTime::Format::ISO8601 qw();
use Digest::MD5 qw/md5_hex/;
use Log::Log4perl qw(:easy);
use LWP::Protocol::http;
push @LWP::Protocol::http::EXTRA_SOCK_OPTS, MaxHeaderLines => 256;
use Moose;
use Net::Domain qw(hostfqdn);
use Test::More;
use URI;
use YAML::XS qw(LoadFile);
use Data::Dumper;

use NGCP::API::TestFramework::RequestBuilder;
use NGCP::API::TestFramework::Client;
use NGCP::API::TestFramework::TestExecutor;

has 'file_path' => (
    isa => 'Str',
    is => 'rw'
);

has 'unique_id' => (
    isa => 'Str',
    is => 'ro'
);

sub run {
    my ( $self ) = @_;

    my $test_case_name = $self->file_path;
    $test_case_name =~ s/.+\/(\w+).yaml/$1/;
    chomp $test_case_name;
    Log::Log4perl->easy_init( { level    => $DEBUG,
                                file     => ">>/results/$test_case_name.log",
                                category => "NGCP::API::TestFramework::Client",
                                layout   => '%d - %F{1} line %L - %M: %m%n' },
                              { level    => $DEBUG,
                                file     => ">>/results/$test_case_name.log",
                                category => "NGCP::API::TestFramework::RequestBuilder",
                                layout   => '%d - %F{1} line %L - %M: %m%n' },
                              { level    => $DEBUG,
                                file     => ">>/results/$test_case_name.log",
                                category => "NGCP::API::TestFramework::TestExecutor",
                                layout   => '%d - %F{1} line %L - %M: %m%n' },
                              { level    => $DEBUG,
                                file     => ">/results/$test_case_name.log",
                                layout   => '%d - %F{1} line %L - %M: %m%n' }
                            );

    INFO( "Started running the Test TestFramework!" );
    unless ( $self->file_path ) {
        return;
    }
    $YAML::XS::DumpCode = 1;
    $YAML::XS::LoadCode = 1;
    $YAML::XS::UseCode = 1;
    $YAML::XS::LoadBlessed = 1;

    INFO( "Loading YAML file." );
    my $testing_data = LoadFile($self->file_path);

    INFO( "Setting up the base URI." );
    my $base_uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
    INFO( "Setting up the RequestBuilder." );
    my $request_builder = NGCP::API::TestFramework::RequestBuilder->new({ base_uri => $base_uri });
    INFO( "Setting up the Client." );
    my $client = NGCP::API::TestFramework::Client->new( { uri => $base_uri } );
    INFO( "Setting up the Test Executor." );
    my $test_executor = NGCP::API::TestFramework::TestExecutor->new();

    # If $self->{retained} is already defined, use its previously collected variables.
    # Otherwise, initialize it with received "unique_id" for fields that need to be unique.
    my $retained = $self->{retained} //= { unique_id => $self->unique_id };

    my $test_case_result = { success => 1, error_count => 0 };

    foreach my $test ( @$testing_data ) {
        $self->process_test( $test_case_name, $base_uri, $request_builder, $client, $test_executor, $retained, $test_case_result, $test );
    }
    return $test_case_result;
}

sub process_test{
    my ( $self, $test_case_name, $base_uri, $request_builder, $client, $test_executor, $retained, $test_case_result, $test ) = @_;

    DEBUG( "In test '".$test->{name}."'" );
    return if ( $test->{skip} );
    if ( !$self->_variables_available( $retained, $test ) ) {
        my $warning = "Warning: Required variable not found for test: $test->{name}.\n";
        WARN( $warning );
        print $warning;
        push @{$test_case_result->{warnings}}, $warning;
        return;
    }

    if ( $test->{type} eq 'include' ) {
        if ( $test->{perl_code} ){
            INFO( "Executing perl code." );
            my $sub = $test->{perl_code};
            $sub->( $retained );
        }
        INFO( "Loading include YAML file." );
        my $include_testing_data = LoadFile("./t/api-rest2/Utils/".$test->{file});
        foreach my $include_test ( @$include_testing_data ) {
            $self->process_test( $include_test->{name}, $base_uri, $request_builder, $client, $test_executor, $retained, $test_case_result, $include_test );
        }
        return;
    }

    # build request
    my $request = $request_builder->build({
        method  => $test->{method},
        path    => $test->{path},
        header  => $test->{header} || undef,
        content => $test->{content} || undef,
        retain  => $retained
    });
    DEBUG ( "Request: ".Dumper $request );

    # handle separate types
    if ( $test->{type} eq 'item' ) {
        INFO( "Performing request." );
        my $result = $client->perform_request($request);
        DEBUG ( "Result: ".Dumper $result );
        if ( $test->{retain} ) {
            INFO( "Storing retained variables." );
            $self->_get_retained_elements( $test->{retain}, $retained, $result );
        }
        if ( $test->{perl_code} ){
            INFO( "Executing perl code." );
            my $sub = $test->{perl_code};
            $sub->( $retained );
        }
        if ( $test->{conditions} ) {
            INFO( "Running tests." );
            my $tests_result = $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} );
            if ( !$tests_result->{success} ) {
                map { print $_." in test case '$test_case_name'\n" } @{$tests_result->{errors}};
                $test_case_result->{success} = 0;
                $test_case_result->{error_count} += scalar @{$tests_result->{errors}};
            }
            if ( $tests_result->{warnings} && scalar @{$tests_result->{warnings}} ) {
                my @warnings = @{$tests_result->{warnings}};
                WARN( @warnings );
                print @warnings;
                push @{$test_case_result->{warnings}}, @warnings;
                return;
            }
        }
    }
    elsif ( $test->{type} eq 'batch' ) {
        foreach my $iteration ( 1..$test->{iterations} ) {
            INFO( "Performing request for iteration $iteration." );
            my $result = $client->perform_request($request);
            DEBUG ( "Result: ".Dumper $result );
            if ( $test->{retain} ) {
                INFO( "Storing retained variables." );
                $self->_get_retained_elements( $test->{retain}, $retained, $result );
            }
            if ( $test->{perl_code} ){
                INFO( "Executing perl code." );
                my $sub = $test->{perl_code};
                $sub->( $retained );
            }
            if ( $test->{conditions} ) {
                INFO( "Running tests." );
                my $tests_result = $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} );
                if ( !$tests_result->{success} ) {
                    map { print $_." in test case '$test_case_name'\n" } @{$tests_result->{errors}};
                    $test_case_result->{success} = 0;
                    $test_case_result->{error_count} += scalar @{$tests_result->{errors}};
                }
            }
        }
    }
    elsif ( $test->{type} eq 'pagination' ) {
        my $nexturi = $test->{path};
        do {
            INFO( "Performing request for pagination." );
            $request->uri( $base_uri.$nexturi );
            my $result = $client->perform_request($request);
            DEBUG ( "Result: ".Dumper $result );
            if ( $test->{retain} ) {
                INFO( "Storing retained variables." );
                $self->_get_retained_elements( $test->{retain}, $retained, $result );
            }
            my $body = decode_json( $result->decoded_content() );

            #build default conditions for pagination
            $test->{conditions}->{is}->{$nexturi} = $body->{_links}->{self}->{href};

            my $colluri = URI->new($base_uri.$body->{_links}->{self}->{href});
            my %q = $colluri->query_form;
            $test->{conditions}->{ok}->{$q{page}} = 'defined';
            $test->{conditions}->{ok}->{$q{rows}} = 'defined';
            my $page = int($q{page});
            my $rows = int($q{rows});
            if($page == 1) {
                $test->{conditions}->{ok}->{'${collection}._links.prev.href'} = 'undefined';
            } else {
                $test->{conditions}->{ok}->{'${collection}._links.prev.href'} = 'defined';
            }
            if(($retained->{collection}->{total_count} / $rows) <= $page) {
                $test->{conditions}->{ok}->{'${collection}._links.next.href'} = 'undefined';
            } else {
                $test->{conditions}->{ok}->{'${collection}._links.next.href'} = 'defined';
            }

            if ( $test->{conditions} ) {
                INFO( "Running tests." );
                my $tests_result = $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} );
                if ( !$tests_result->{success} ) {
                    map { print $_." in test case '$test_case_name'\n" } @{$tests_result->{errors}};
                    $test_case_result->{success} = 0;
                    $test_case_result->{error_count} += scalar @{$tests_result->{errors}};
                }
            }

            if( $body->{_links}->{next}->{href} ) {
                $nexturi = $body->{_links}->{next}->{href};
            } else {
                $nexturi = undef;
            }
        } while ( $nexturi )
    }
    return $test_case_result;
}

sub _get_retained_elements {
    my ( $self, $retain, $retained, $result ) = @_;

    while ( my ( $retain_elem, $retain_value ) = each %{$retain} ) {
        if ( $retain_value =~ /.+\..+/ ) {
            my @splitted_values = split (/\./, $retain_value);
            $retained->{$retain_elem} = $self->_retrieve_from_composed_key( $result, \@splitted_values, $retain_elem );
        }
        elsif ( $retain_value eq 'body' ) {
            $retained->{$retain_elem} = decode_json( $result->decoded_content() );
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

    return 0 if ( $test->{path} && $test->{path} =~ /\$\{(.*)\}/ && !$retained->{$1} );

    # substitute variables in content
    if ( $test->{content} && ref $test->{content} eq 'HASH' ) {
        foreach my $content_key (keys %{$test->{content}}) {
            return 0 if ( $test->{content}->{$content_key} && $test->{content}->{$content_key} =~ /\$\{(.*)\}/ && !$retained->{$1} );
        }
    }
    return 1;
}

1;
