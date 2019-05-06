package NGCP::TestFramework;

use strict;
use warnings;
use Cpanel::JSON::XS;
use Data::Walk;
use DateTime qw();
use DateTime::Format::Strptime qw();
use DateTime::Format::ISO8601 qw();
use Digest::MD5 qw/md5_hex/;
use Moose;
use Net::Domain qw(hostfqdn);
use Test::More;
use URI;
use YAML::XS qw(LoadFile);
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
    $YAML::XS::DumpCode = 1;
    $YAML::XS::LoadCode = 1;
    $YAML::XS::UseCode = 1;
    $YAML::XS::LoadBlessed = 1;

    my $testing_data = LoadFile($self->file_path);

    my $base_uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
    my $request_builder = NGCP::TestFramework::RequestBuilder->new({ base_uri => $base_uri });
    my $client = NGCP::TestFramework::Client->new( { uri => $base_uri, log_debug => 0 } );
    my $test_executor = NGCP::TestFramework::TestExecutor->new();

    # initializing time to add to fields which need to be unique
    my $retained = { unique_id => int(rand(100000)) };

    foreach my $test ( @$testing_data ) {
        next if ( $test->{skip} );

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
            if ( $test->{perl_code} ){
                my $sub = $test->{perl_code};
                warn Dumper $sub;
                $sub->( $retained );
            }
            $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} ) if ( $test->{conditions} );
        }
        elsif ( $test->{type} eq 'batch' ) {
            foreach my $iteration ( 1..$test->{iterations} ) {
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

                $test_executor->run_tests( $test->{conditions}, $result, $retained, $test->{name} ) if ( $test->{conditions} );

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

    return 0 if ( $test->{path} =~ /\$\{(.*)\}/ && !$retained->{$1} );

    # substitute variables in content
    if ( $test->{content} && ref $test->{content} eq 'HASH' ) {
        foreach my $content_key (keys %{$test->{content}}) {
            return 0 if ( $test->{content}->{$content_key} =~ /\$\{(.*)\}/ && !$retained->{$1} );
        }
    }
    return 1;
}

1;
