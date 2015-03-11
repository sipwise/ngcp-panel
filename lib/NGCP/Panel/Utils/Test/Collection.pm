package NGCP::Panel::Utils::Test::Collection;

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
has 'methods' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {
        'collection' =>{
            'all'     => {map {$_ => 1} qw/GET HEAD OPTIONS POST/}, 
            'allowed' => {map {$_ => 1} qw/GET HEAD OPTIONS POST/}, #some default
        },
        'item' =>{
            'all'     => {map {$_ => 1} qw/GET HEAD OPTIONS PUT PATCH POST DELETE/}, 
            'allowed' => {map {$_ => 1} qw/GET HEAD OPTIONS PUT PATCH DELETE/}, #some default
        },
    } },
);
has 'content_type' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{
        POST  => 'application/json',
        PUT   => 'application/json',
        PATCH => 'application/json-patch+json',
    }},
);
#state variables - smth like predefined stash
has 'DATA_ITEM' => (
    is => 'rw',
    isa => 'Ref',
);
has 'DATA_ITEM_STORE' => (
    is => 'rw',
    isa => 'Ref',
);
after 'DATA_ITEM_STORE' => sub {
    my $self = shift;
    if(@_){
        #$self->DATA_ITEM($self->DATA_ITEM_STORE);
        $self->form_data_item;
    }
};
has 'DATA_CREATED' => (
    is => 'rw',
    isa => 'HashRef',
    builder => 'clear_data_created',
);
has 'URI_CUSTOM' =>(
    is => 'rw',
    isa => 'Str',
);
has 'URI_CUSTOM_STORE' =>(
    is => 'rw',
    isa => 'Str',
);
before 'URI_CUSTOM' => sub {
    my $self = shift;
    if(@_){
        if($self->URI_CUSTOM_STORE){
            die('Attempt to set custom uri second time without restore. Custom uri is not a stack. Clear or restore it first, please.');
        }else{
            $self->URI_CUSTOM_STORE($self->URI_CUSTOM);
        }
    }
};
has 'ENCODE_CONTENT' => (
    is => 'rw',
    isa => 'Str',
    default => 'json',
);
sub _init_ua {
    my $self = shift;
    my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
        "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
    my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
        $valid_ssl_client_cert;
    my $ssl_ca_cert = $ENV{ API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";
    my $ua = LWP::UserAgent->new;
    $ua->ssl_opts(
        SSL_cert_file   => $valid_ssl_client_cert,
        SSL_key_file    => $valid_ssl_client_key,
        SSL_ca_file     => $ssl_ca_cert,
    );
    #$ua->credentials( $self->base_uri, '', 'administrator', 'administrator' );
    #$ua->ssl_opts(
    #    verify_hostname => 0,
    #    SSL_verify_mode => 0x00,
    #);
    return $ua;
};
sub clear_data_created{
    my($self) = @_;
    $self->DATA_CREATED({
        ALL   => {},
        FIRST => undef,
    });
    return $self->DATA_CREATED;
}
sub form_data_item{
    my($self, $data_cb, $data_cb_data) = @_;
    $self->{DATA_ITEM} ||= clone($self->DATA_ITEM_STORE);
    (defined $data_cb) and $data_cb->($self->DATA_ITEM,$data_cb_data);
    return $self->DATA_ITEM;
}
sub get_hal_name{
    my($self) = @_;
    return "ngcp:".$self->name;
}
sub restore_uri_custom{
    my($self) = @_;
    $self->URI_CUSTOM($self->URI_CUSTOM_STORE);
    $self->URI_CUSTOM_STORE(undef);
}
sub get_uri_collection{
    my($self) = @_;
    return $self->base_uri."/api/".$self->name.($self->name ? "/" : "");
}
sub get_uri_firstitem{
    my($self) = @_;
    if(!$self->DATA_CREATED->{FIRST}){
        my($res,$list_collection,$req) = $self->check_item_get($self->get_uri_collection."?page=1&rows=1");
        my $hal_name = $self->get_hal_name;
        if(ref $list_collection->{_links}->{$hal_name} eq "HASH") {
            $self->DATA_CREATED->{FIRST} = $list_collection->{_links}->{$hal_name}->{href};
        } else {
            $self->DATA_CREATED->{FIRST} = $list_collection->{_embedded}->{$hal_name}->[0]->{_links}->{self}->{href};
        }
    }
    $self->DATA_CREATED->{FIRST} //= '';
    return $self->base_uri.'/'.$self->DATA_CREATED->{FIRST};
}

sub get_uri_current{
    my($self) = @_;
    $self->URI_CUSTOM and return $self->URI_CUSTOM;
    return $self->get_uri_firstitem;
}
sub encode_content{
    my($self,$content, $type) = @_;
    $type //= $self->ENCODE_CONTENT;
    my %json_types = (
        'application/json' => 1,
        'application/json-patch+json' => 1,
        'json' => 1,
    );
    #print "content=$content;\n\n";
    if($content){
        if( $json_types{$type} && (('HASH' eq ref $content) ||('ARRAY' eq ref $content))  ){
            return JSON::to_json($content);
        }
    }
    return $content;
}
sub request{
    my($self,$req) = @_;
    #print $req->as_string; 
    $self->ua->request($req);
}

sub get_request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    #This is for multipart/form-data cases
    $content = $self->encode_content($content, $self->content_type->{PUT});
    my $req = POST $uri, 
        Content_Type => $self->content_type->{POST}, 
        $content ? ( Content => $content ) : ();
    $req->method('PUT');
    $req->header('Prefer' => 'return=representation');
    return $req;
}
sub get_request_patch{
    my($self,$uri) = @_;
    $uri ||= $self->get_uri_current;
    my $req = HTTP::Request->new('PATCH', $uri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => $self->content_type->{PATCH} );
    return $req;
}
sub request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    my $req = $self->get_request_put( $content, $uri );
    my $res = $self->request($req);
    #print Dumper $res;
    
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return wantarray ? ($res,$err,$req) : $res;
}
sub request_patch{
    my($self,$content,$uri, $req) = @_;
    $uri ||= $self->get_uri_current;
    $req ||= $self->get_request_patch($uri);
    #patch is always a json
    $content = $self->encode_content($content, $self->content_type->{PATCH});
    $content and $req->content($content);
    my $res = $self->request($req);
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
    $content = $self->encode_content($content, $self->content_type->{POST} );
    #form-data is set automatically, despite on $self->content_type->{POST}
    my $req = POST $self->get_uri_collection, 
        Content_Type => $self->content_type->{POST}, 
        Content => $content;
    my $res = $self->request($req);
    my $err = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return ($res,$err,$req);
};



sub request_options{
    my ($self,$uri) = @_;
    # OPTIONS tests
    $uri ||= $self->get_uri_current;
    my $req = HTTP::Request->new('OPTIONS', $uri);
    my $res = $self->request($req);
    my $content = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return($req,$res,$content);
}
sub request_delete{
    my ($self,$uri) = @_;
    # DELETE tests
    #no auto rows for deletion
    my $req = HTTP::Request->new('DELETE', $uri);
    my $res = $self->request($req);
    my $content = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return($req,$res,$content);
}
sub check_options_collection{
    my ($self) = @_;
    # OPTIONS tests
    my $req = HTTP::Request->new('OPTIONS', $self->get_uri_collection );
    my $res = $self->request($req);
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-".$self->name, "check Accept-Post header in options response");
    $self->check_methods($res,'collection');
}
sub check_options_item{
    my ($self,$uri) = @_;
    # OPTIONS tests
    $uri ||= $self->get_uri_current;
    my $req = HTTP::Request->new('OPTIONS', $uri);
    my $res = $self->request($req);
    $self->check_methods($res,'item');
}
sub check_methods{
    my($self, $res, $area) = @_;
    is($res->code, 200, "check $area options request");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(keys %{$self->methods->{$area}->{all}} ) {
        if(exists $self->methods->{$area}->{allowed}->{$opt}){
            ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
            ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
        }else{
            ok(!grep(/^$opt$/, @hopts), "check for absence of '$opt' in Allow header");
            ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for absence of '$opt' in body");       
        }
    }
}
sub check_create_correct{
    my($self, $number, $uniquizer_cb, $keep_data) = @_;
    if(!$keep_data){
        $self->clear_data_created;
    }
    $self->DATA_CREATED->{ALL} //= {};
    for(my $i = 1; $i <= $number; ++$i) {
        my ($res, $err) = $self->request_post( $uniquizer_cb , undef, { i => $i} );
        is($res->code, 201, "create test item $i");
        my $location = $res->header('Location');
        if($location){
            $self->DATA_CREATED->{ALL}->{$location} = $i;
            $self->DATA_CREATED->{FIRST} = $location unless $self->DATA_CREATED->{FIRST};
        }
    }
}
sub check_delete_use_created{
    my($self,$uri) = @_;
    my @uris = $uri ? ($uri) : keys $self->DATA_CREATED->{ALL};
    foreach my $del_uri(@uris){
        my($req,$res,$content) = $self->request_delete($self->base_uri.$del_uri);
        is($res->code, 204, "check delete item $del_uri");
    }
}
sub check_list_collection{
    my($self, $check_embedded_cb) = @_;
    my $nexturi = $self->get_uri_collection."?page=1&rows=5";
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
        ok($rows != 0, "check existance of the 'rows'");
        if($page == 1) {
            ok(!exists $list_collection->{_links}->{prev}->{href}, "check absence of 'prev' on first page");
        } else {
            ok(exists $list_collection->{_links}->{prev}->{href}, "check existence of 'prev'");
        }
        if(($rows != 0) && ($list_collection->{total_count} / $rows) <= $page) {
            ok(!exists $list_collection->{_links}->{next}->{href}, "check absence of 'next' on last page");
        } else {
            ok(exists $list_collection->{_links}->{next}->{href}, "check existence of 'next'");
        }

        if($list_collection->{_links}->{next}->{href}) {
            $nexturi = $self->base_uri . $list_collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        my $hal_name = $self->get_hal_name;
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
    $listed //= [];#to avoid error about not array reference
    $created_items //= [];
    foreach (@$listed){
        delete $created_items->{$_};
    }
    is(scalar(keys %{$created_items}), 0, "check if all created test items have been foundin the list");
}

sub check_item_get{
    my($self,$uri) = @_;
    $uri ||= $self->get_uri_current;
    my $req = HTTP::Request->new('GET', $uri);
    my $res = $self->request($req);
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
    my $res = $self->request($req);
    is($res->code, 415, "check put missing content type");
}
sub check_put_content_type_wrong{
    my($self) = @_;
    # check if it fails with unsupported content type
    my $req = $self->get_request_put;
    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/xxx');
    my $res = $self->request($req);
    is($res->code, 415, "check put invalid content type");
}
sub check_put_prefer_wrong{
    my($self) = @_;
    # check if it fails with invalid Prefer
    my $req = $self->get_request_put;
    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=invalid");
    my $res = $self->request($req);
    is($res->code, 400, "check put invalid prefer");
}

sub check_put_body_empty{
    my($self) = @_;
    # check if it fails with missing body
    my $req = $self->get_request_put;
    #$req->remove_header('Prefer');
    #$req->header('Prefer' => "return=representation");
    my $res = $self->request($req);
    is($res->code, 400, "check put no body");
}
sub check_get2put{
    my($self,$put_data_cb, $uri) = @_;
    #$req->remove_header('Prefer');
    #$req->header('Prefer' => "return=representation");
    # PUT same result again
    my ($get_res, $item_first_get, $get_req) = $self->check_item_get($uri);
    my $item_first_put = clone($item_first_get);
    delete $item_first_put->{_links};
    delete $item_first_put->{_embedded};
    # check if put is ok
    (defined $put_data_cb) and $put_data_cb->($item_first_put);
    my ($put_res,$item_put_result) = $self->request_put( $item_first_put, $uri );
    is($put_res->code, 200, "check put successful");
    is_deeply($item_first_get, $item_put_result, "check put if unmodified put returns the same");
}
sub check_put_bundle{
    my($self) = @_;
    $self->check_put_content_type_empty;
    $self->check_put_content_type_wrong;
    $self->check_put_prefer_wrong;
    $self->check_put_body_empty;
}
sub check_patch_correct{
    my($self,$content) = @_;
    my ($res,$mod_model,$req) = $self->request_patch( $content );
    is($res->code, 200, "check patched item");
    is($mod_model->{_links}->{self}->{href}, $self->DATA_CREATED->{FIRST}, "check patched self link");
    is($mod_model->{_links}->{collection}->{href}, '/api/'.$self->name.'/', "check patched collection link");
    return ($res,$mod_model,$req);
}

sub check_patch_prefer_wrong{
    my($self) = @_;
    my $req = $self->get_request_patch;
    $req->remove_header('Prefer');
    $req->header('Prefer' => 'return=minimal');
    my $res = $self->request($req);
    is($res->code, 415, "check patch invalid prefer");
}
sub check_patch_content_type_empty{
    my($self) = @_;
    my $req = $self->get_request_patch;
    $req->remove_header('Content-Type');
    my $res = $self->request($req);
    is($res->code, 415, "check patch missing media type");
}

sub check_patch_content_type_wrong{
    my($self) = @_;
    my $req = $self->get_request_patch;
    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/xxx');
    my $res = $self->request($req);
    is($res->code, 415, "check patch invalid media type");
}

sub check_patch_body_empty{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch;
    is($res->code, 400, "check patch missing body");
    like($content->{message}, qr/is missing a message body/, "check patch missing body response");
}

sub check_patch_body_notarray{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        { foo => 'bar' },
    );
    is($res->code, 400, "check patch no array body");
    like($content->{message}, qr/must be an array/, "check patch missing body response");
}

sub check_patch_op_missed{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ foo => 'bar' }],
    );
    is($res->code, 400, "check patch no op in body");
    like($content->{message}, qr/must have an 'op' field/, "check patch no op in body response");
}

sub check_patch_op_wrong{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'bar' }],
    );
    is($res->code, 400, "check patch invalid op in body");
    like($content->{message}, qr/Invalid PATCH op /, "check patch no op in body response");
}

sub check_patch_opreplace_paramsmiss{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'replace' }],
    );
    is($res->code, 400, "check patch missing fields for op");
    like($content->{message}, qr/Missing PATCH keys /, "check patch missing fields for op response");
}

sub check_patch_opreplace_paramsextra{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'replace', path => '/foo', value => 'bar', invalid => 'sna' }],
    );
    is($res->code, 400, "check patch extra fields for op");
    like($content->{message}, qr/Invalid PATCH key /, "check patch extra fields for op response");
}

sub check_patch_bundle{
    my($self) = @_;
    #$self->check_patch_prefer_wrong;
    $self->check_patch_content_type_wrong;
    $self->check_patch_content_type_empty;
    $self->check_patch_body_empty;
    $self->check_patch_body_notarray;
    $self->check_patch_op_missed;
    $self->check_patch_op_wrong;
    $self->check_patch_opreplace_paramsmiss;
    $self->check_patch_opreplace_paramsextra;
}
sub check_bundle{
    my($self) = @_;
    $self->check_options_collection;
    # iterate over collection to check next/prev links and status
    my $listed = $self->check_list_collection();
    $self->check_created_listed($listed);
    # test model item
    $self->check_options_item;
    $self->check_put_bundle;
    $self->check_patch_bundle;
}
1;