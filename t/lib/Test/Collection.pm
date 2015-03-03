package Test::Collection;

use strict;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;
use Moose;
use Clone qw/clone/;

has 'ua' => (
    is => 'rw',
    isa => 'LWP::UserAgent',
    builder => '_init_ua',
);
has 'base_uri' => (
    is => 'ro',
    isa => 'Str',
    default => 'https://192.168.56.7:1444' || $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443'),
); 
has 'name' => (
    is => 'rw',
    isa => 'Str',
);
has 'embedded' => (
    is => 'rw',
    isa => 'ArrayRef',
);

#state variables - smth like predefined stash
has 'CONTENT_TYPE' => (
    is => 'rw',
    isa => 'Str',
);
has 'DATA_ITEM' => (
    is => 'rw',
    isa => 'Ref',
);
has 'DATA_CREATED' => (
    is => 'rw',
    isa => 'ArrayRef',
);

sub _init_ua {
    my $self = shift;
    my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
        "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
    my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
        $valid_ssl_client_cert;
    my $ssl_ca_cert = $ENV{ API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";
    my $ua = LWP::UserAgent->new;
    $ua->credentials( $self->base_uri, '', 'administrator', 'administrator' );
    #$ua->ssl_opts(
    #    SSL_cert_file   => $valid_ssl_client_cert,
    #    SSL_key_file    => $valid_ssl_client_key,
    #    SSL_ca_file     => $ssl_ca_cert,
    #);
    $ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0x00,
    );
    return $ua;
};
sub request_post{
    my($self,$data_cb,$data_in) = @_;
    my $data = $data_in || clone($self->DATA_ITEM);
    $data_cb and $data_cb->($data);
    my $content = {
        $data->{json} ? ( json => JSON::to_json(delete $data->{json}) ) : (),
        %$data,
    };
    my $req = POST $self->base_uri.'/api/'.$self->name.'/', Content_Type => $self->CONTENT_TYPE, Content => $content;
    my $res = $self->ua->request($req);
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return ($res,$err);
};
sub check_options_collection{
    my $self = shift;
    # OPTIONS tests
    my $req = HTTP::Request->new('OPTIONS', $self->base_uri."/api/".$self->name."/");
    my $res = $self->ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-".$self->name, "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}
sub check_list_collection{
    my($self, $check_embedded_cb) = @_;
    my $nexturi = $self->base_uri."/api/".$self->name."/?page=1&rows=5";
    my @href = ();
    do {
        my $res = $self->ua->get($nexturi);
        is($res->code, 200, "fetch model page");
        my $list_collection = JSON::from_json($res->decoded_content);
        my $selfuri = $self->base_uri . $list_collection->{_links}->{self}->{href};
        is($selfuri, $nexturi, "check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        ok($list_collection->{total_count} > 0, "check 'total_count' of collection");

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, "check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $list_collection->{_links}->{prev}->{href}, "check absence of 'prev' on first page");
        } else {
            ok(exists $list_collection->{_links}->{prev}->{href}, "check existence of 'prev'");
        }
        if(($list_collection->{total_count} / $rows) <= $page) {
            ok(!exists $list_collection->{_links}->{next}->{href}, "check absence of 'next' on last page");
        } else {
            ok(exists $list_collection->{_links}->{next}->{href}, "check existence of 'next'");
        }

        if($list_collection->{_links}->{next}->{href}) {
            $nexturi = $self->base_uri . $list_collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        my $hal_name = "ngcp:".$self->name;
        ok(((ref $list_collection->{_links}->{$hal_name} eq "ARRAY" ) || 
             (ref $list_collection->{_links}->{$hal_name} eq "HASH" ) ), "check if 'ngcp:".$self->name."' is array/hash-ref");

        my $check_embedded = sub {
            my($embedded) = @_;
            $check_embedded_cb and $check_embedded_cb->($embedded);
            foreach my $embedded_name(@$self->embedded){
                ok(exists $embedded->{_links}->{'ngcp:'.$embedded_name}, "check presence of ngcp:$embedded_name relation");
            }
        };

        # it is really strange - we check that the only element of the _links will be hash - and after this treat _embedded as hash too
        #the only thing that saves us - we really will not get into the if ever
        if(ref $list_collection->{_links}->{$hal_name} eq "HASH") {
            $check_embedded->($list_collection->{_embedded}->{$hal_name});
            push @href, $list_collection->{_links}->{$hal_name}->{href};
        } else {
            foreach my $item_c(@{ $list_collection->{_links}->{$hal_name} }) {
                push @href, $item_c->{href};
            }
            foreach my $item_c(@{ $list_collection->{_embedded}->{$hal_name} }) {
            # these relations are only there if we have zones/fees, which is not the case with an empty model
                $check_embedded->($item_c);
                push @href, $item_c->{_links}->{self}->{href};
            }
        }
    } while($nexturi);
    return \@href;
}
sub check_created_existance{
    my($self) = shift;
}
1;