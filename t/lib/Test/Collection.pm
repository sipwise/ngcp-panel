package Test::Collection;

use strict;
use Test::More;
use Moose;
use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Net::Domain qw(hostfqdn);
use URI;
use Clone qw/clone/;

use Data::Dumper;


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
has 'embedded_resources' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
);

#state variables - smth like predefined stash
has 'CONTENT_TYPE' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{
        POST  => 'application/json',
        PUT   => 'application/json',
        PATCH => 'application/json-patch+json',
    }},
);
has 'DATA_ITEM' => (
    is => 'rw',
    isa => 'Ref',
);
has 'DATA_CREATED' => (
    is => 'rw',
    isa => 'HashRef',
    builder => 'clear_created_data',
);
has 'REQUEST' => (
    is => 'rw',
    isa => 'HTTP::Request::Common',
);

sub _init_ua {
    my $self = shift;
    my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
        "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
    my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
        $valid_ssl_client_cert;
    my $ssl_ca_cert = $ENV{ API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";
    my $ua = LWP::UserAgent->new;
    #$ua->ssl_opts(
    #    SSL_cert_file   => $valid_ssl_client_cert,
    #    SSL_key_file    => $valid_ssl_client_key,
    #    SSL_ca_file     => $ssl_ca_cert,
    #);
    $ua->credentials( $self->base_uri, '', 'administrator', 'administrator' );
    $ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0x00,
    );
    return $ua;
};
sub clear_created_data{
    my($self) = @_;
    $self->DATA_CREATED({
        ALL   => {},
        FIRST => undef,
    });
    return $self->DATA_CREATED;
}
sub get_firstitem_uri{
    my($self) = @_;
    #print Dumper $self->DATA_CREATED->{FIRST};
    return $self->base_uri.'/'.$self->DATA_CREATED->{FIRST};
}

sub get_request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_firstitem_uri;
    #This is for multipart/form-data cases
    my $req = POST $uri, 
        Content_Type => $self->CONTENT_TYPE->{POST}, 
        $content ? ( Content => $content ) : ();
    $req->method('PUT');
    $req->header('Prefer' => 'return=representation');
    return $req;
}
sub get_request_patch{
    my($self,$uri) = @_;
    $uri ||= $self->get_firstitem_uri;
    my $req = HTTP::Request->new('PATCH', $uri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => $self->CONTENT_TYPE->{PATCH} );
    return $req;
}
sub request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_firstitem_uri;
    my $req = $self->get_request_put( $content, $uri );
    my $res = $self->ua->request($req);
    #print Dumper $res;
    
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return wantarray ? ($res,$err,$req) : $res;
}
sub request_patch{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_firstitem_uri;
    my $req = $self->get_request_patch($uri);
    $req->content(JSON::to_json(
        $content
    ));
    my $res = $self->ua->request($req);
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    #print Dumper [$res,$err,$req];
    return ($res,$err,$req);
}

sub request_post{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $data = $data_in || clone($self->DATA_ITEM);
    defined $data_cb and $data_cb->($data, $data_cb_data);
    my $content = {
        $data->{json} ? ( json => JSON::to_json(delete $data->{json}) ) : (),
        %$data,
    };
    #form-data is set automatically, despite on $self->CONTENT_TYPE->{POST}
    my $req = POST $self->base_uri.'/api/'.$self->name.'/', 
        Content_Type => $self->CONTENT_TYPE->{POST}, 
        Content => $content;
    my $res = $self->ua->request($req);
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return ($res,$err,$req);
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
sub check_options_item{
    my ($self,$uri) = shift;
    $uri ||= $self->get_firstitem_uri;
    my $req = HTTP::Request->new('OPTIONS', $uri);
    my $res = $self->ua->request($req);
    is($res->code, 200, "check options on item");
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    my $opts = JSON::from_json($res->decoded_content);
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS PUT PATCH )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( POST DELETE )) {
        ok(!grep(/^$opt$/, @hopts), "check for absence of '$opt' in Allow header");
        ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for absence of '$opt' in body");
    }
}
sub check_create_correct{
    my($self, $number, $uniquizer_cb, $keep_data) = @_;
    if(!$keep_data){
        $self->clear_created_data;
    }
    for(my $i = 1; $i <= $number; ++$i) {
        my ($res, $err) = $self->request_post( $uniquizer_cb , undef, { i => $i} );
        is($res->code, 201, "create test item $i");
        $self->DATA_CREATED->{ALL}->{$res->header('Location')} = $i;
        $self->DATA_CREATED->{FIRST} = $res->header('Location') unless $self->DATA_CREATED->{FIRST};
    }
}
sub check_list_collection{
    my($self, $check_embedded_cb) = @_;
    my $nexturi = $self->base_uri."/api/".$self->name."/?page=1&rows=5";
    my @href = ();
    do {
        #print "nexturi=$nexturi;\n";
        my $res = $self->ua->get($nexturi);
        is($res->code, 200, "fetch collection page");
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
            defined $check_embedded_cb and $check_embedded_cb->($embedded);
            foreach my $embedded_name(@{$self->embedded_resources}){
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

sub check_created_listed{
    my($self,$listed) = @_;
    my $created_items = clone($self->DATA_CREATED->{ALL});
    foreach (@$listed){
        delete $created_items->{$_};
    }
    is(scalar(keys %{$created_items}), 0, "check if all created test items have been foundin the list");
}

sub check_item_get{
    my($self,$uri) = @_;
    $uri ||= $self->get_firstitem_uri;
    my $req = HTTP::Request->new('GET', $uri);
    my $res = $self->ua->request($req);
    is($res->code, 200, "fetch one item");
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return wantarray ? ($res, $err, $req) : $res;
}

sub check_put_content_type_empty{
    my($self) = @_;
    # check if it fails without content type
    my $req = $self->get_request_put;
    $req->remove_header('Content-Type');
    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=minimal");
    my $res = $self->ua->request($req);
    is($res->code, 415, "check put missing content type");
}
sub check_put_content_type_wrong{
    my($self) = @_;
    # check if it fails with unsupported content type
    my $req = $self->get_request_put;
    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/xxx');
    my $res = $self->ua->request($req);
    is($res->code, 415, "check put invalid content type");
}
sub check_put_prefer_wrong{
    my($self) = @_;
    # check if it fails with invalid Prefer
    my $req = $self->get_request_put;
    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=invalid");
    my $res = $self->ua->request($req);
    is($res->code, 400, "check put invalid prefer");
}

sub check_put_body_empty{
    my($self) = @_;
    # check if it fails with missing body
    my $req = $self->get_request_put;
    #$req->remove_header('Prefer');
    #$req->header('Prefer' => "return=representation");
    my $res = $self->ua->request($req);
    is($res->code, 400, "check put no body");
}
sub check_get2put{
    my($self,$put_data_cb) = @_;
    #$req->remove_header('Prefer');
    #$req->header('Prefer' => "return=representation");
    # PUT same result again
    my (undef, $item_first_get) = $self->check_item_get;
    my $item_first_put = clone($item_first_get);
    delete $item_first_put->{_links};
    delete $item_first_put->{_embedded};
    # check if put is ok
    (defined $put_data_cb) and $put_data_cb->($item_first_put);
    my ($res,$item_put_result) = $self->request_put( $item_first_put );
    is($res->code, 200, "check put successful");
    is_deeply($item_first_get, $item_put_result, "check put if unmodified put returns the same");
}
sub check_put_bundle{
    my($self) = @_;
    $self->check_put_content_type_empty;
    $self->check_put_content_type_wrong;
    $self->check_put_prefer_wrong;
    $self->check_put_body_empty;
}
sub check_patch{
    my($self,$content) = @_;
    my ($res,$mod_model,$req) = $self->request_patch( $content );
    is($res->code, 200, "check patched model item");
    is($mod_model->{_links}->{self}->{href}, $self->DATA_CREATED->{FIRST}, "check patched self link");
    is($mod_model->{_links}->{collection}->{href}, '/api/'.$self->name.'/', "check patched collection link");
    return ($res,$mod_model,$req);
}
1;