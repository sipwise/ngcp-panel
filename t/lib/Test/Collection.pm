package Test::Collection;
#todo: later package should be split into 2: apiclient and testcollection
#testcollection will keep object of the apiclient

use strict;
use threads qw();
use threads::shared qw();
use Test::More;
use Moose;
use JSON;
use LWP::UserAgent;
use Config::General;
use HTTP::Request::Common;
use Net::Domain qw(hostfqdn);
use URI;
use URI::Escape;
use Clone qw/clone/;
use File::Basename;
use Test::HTTPRequestAsCurl;
use Test::ApplyPatch;
use Data::Dumper;
use File::Slurp qw/write_file/;
use Storable;
use Carp qw(cluck longmess shortmess);
use IO::Uncompress::Unzip;
use File::Temp qw();

Moose::Exporter->setup_import_methods(
    as_is     => [ 'is_int' ],
);
my $tmpfilename : shared;
my $requests_time = [];
my $failed_http_tests = [];

has 'ssl_cert' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => 'init_ssl_cert',
);

has 'data_cache_file' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub {'/tmp/ngcp-api-test-data-cache';},
);

has 'cache_data' => (
    is => 'ro',
    isa => 'Bool',
    lazy => 1,
    default => $ENV{API_CACHE_FAKE_DATA} // 0,
);

has 'local_test' => (
    is => 'rw',
    isa => 'Str',
    default => sub {$ENV{LOCAL_TEST} // ''},
);

has 'DEBUG' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'DEBUG_ONLY' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'QUIET_DELETION' => (
    is => 'rw',
    isa => 'Bool',
    default => 1,
);

has 'ALLOW_EMPTY_COLLECTION' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'IS_EMPTY_COLLECTION' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'NO_ITEM_MODULE' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'catalyst_config' => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    builder => 'init_catalyst_config',
);

has 'panel_config' => (
    is => 'rw',
    isa => 'HashRef',
);

has 'runas_role' => (
    is => 'rw',
    isa => 'Str',
    default => 'default',
);

has 'ua' => (
    is => 'rw',
    isa => 'LWP::UserAgent',
    lazy => 1,
    builder => 'init_ua',
);

has 'base_uri' => (
    is => 'rw',
    isa => 'Str',
    lazy => 1,
    default => sub {
        $_[0]->local_test
        ? ( length($_[0]->local_test)>1 ? $_[0]->local_test : 'https://127.0.0.1:1443' )
        : $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
    },
);

has 'name' => (
    is => 'rw',
    isa => 'Str',
);

has 'subscriber_user' => (
    is => 'rw',
    isa => 'Str',
);

has 'subscriber_pass' => (
    is => 'rw',
    isa => 'Str',
);

has 'reseller_admin_user' => (
    is => 'rw',
    isa => 'Str',
);

has 'reseller_admin_pass' => (
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

has 'KEEP_CREATED' =>(
    is => 'rw',
    isa => 'Bool',
    default => 1,
);

has 'EXPECTED_AMOUNT_CREATED' =>(
    is => 'rw',
    isa => 'Int',
    default => 0,
);

#amount of the collection requests to check listing implementation and output parameters as page, first, last pages uris and rows
#So, it is supposed, that we will perform CHECK_LIST_LIMIT requests to collection in check_list_collection method, or, max CHECK_LIST_LIMIT + 1
has 'CHECK_LIST_LIMIT' =>(
    is => 'rw',
    isa => 'Int',
    default => 0,
);

has 'DATA_LOADED' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub{{}},
);

has 'URI_CUSTOM' =>(
    is => 'rw',
    isa => 'Str',
);

has 'QUERY_PARAMS' =>(
    is => 'rw',
    isa => 'Str',
    default => '',
);

has 'PAGE' =>(
    is => 'rw',
    isa => 'Str',
    default => '1',
);

has 'ROWS' =>(
    is => 'rw',
    isa => 'Str',
    default => '1',
);

has 'NO_COUNT' =>(
    is => 'rw',
    isa => 'Str',
    default => '',
);

has 'NO_TEST_NO_COUNT' =>(
    is => 'rw',
    isa => 'Str',
    default => '0',
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

sub set{
    my $self = shift;
    my %params = @_;
    my $prev_state = {};
    while (my ($variable, $value) = each %params){
        $prev_state->{$variable} = $self->$variable;
        $self->$variable($value);
    }
    return $prev_state;
}

sub get_cloned{
    my $self = shift;
    my @params = @_;
    my $state = {};
    foreach my $variable (@params){
        $state->{$variable} = clone( $self->$variable );
    }
    return $state;
}

sub init_catalyst_config{
    my $self = shift;
    my $config;
    my $restored;
    if($self->cache_data){
        $restored = $self->get_cached_data;
        if($restored->{loaded} && $restored->{loaded}->{metaconfigdefs}){
            $config = $restored->{loaded}->{metaconfigdefs}->{content};
        }
    }
    if(!$config){
        my($res,$list_collection,$req) = $self->check_item_get($self->normalize_uri('/api/metaconfigdefs/'));
        my $location;
        ($config,$location) = $self->get_hal_from_collection($list_collection);
        if($self->cache_data){
            $restored->{loaded} //= {};
            $restored->{loaded}->{metaconfigdefs} = { content => $config, location => $location };
            store $restored, $self->data_cache_file;
        }
    }
    $self->{catalyst_config} = $config;
    $self->{panel_config} = $config->{file};
    return $self->{catalyst_config};
}

sub init_ua {
    my $self = shift;
    return $self->_create_ua(1);
}

sub _create_ua {
    my ($self,$init_cert) = @_;
    my $ua = LWP::UserAgent->new;
    my $uri = $self->base_uri;
    $uri =~ s/^https?:\/\///;
    my($user,$pass,$role,$realm) = $self->get_role_credentials();
    $ua->credentials( $uri, $realm, $user, $pass);
    $ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
    if($init_cert) {
        $self->init_ssl_cert($ua, $role);
    }
    return $ua;
}

sub init_ssl_cert {
    my ($self, $ua, $role) = @_;
    $role //= 'default';
    if($role ne "default" && $role ne "admin" && $role ne "reseller") {
        $ua->ssl_opts(
            SSL_cert_file => undef,
            SSL_key_file => undef,
        );
        return;
    }
    lock $tmpfilename;
    unless ($tmpfilename && -e $tmpfilename) {
        my $_ua = $ua // $self->_create_ua(0);
        my $res = $_ua->post(
            $self->base_uri . '/api/admincerts/',
            Content_Type => 'application/json',
            Content => '{}'
        );
        unless($res->is_success) {
            die "failed to fetch client certificate: " . $res->status_line . "\n";
        }
        my $zip = $res->decoded_content;
        my $z = IO::Uncompress::Unzip->new(\$zip, MultiStream => 0, Append => 1);
        my $data;
        while(!$z->eof() && (my $hdr = $z->getHeaderInfo())) {
            unless($hdr->{Name} =~ /\.pem$/) {
                # wrong file, just read stream, clear buffer and try next
                while($z->read($data) > 0) {}
                $data = undef;
                $z->nextStream();
                next;
            }
            while($z->read($data) > 0) {}
            last;
        }
        $z->close();
        unless($data) {
            die "failed to find PEM file in client certificate zip file\n";
        }
        (my $tmpfh,$tmpfilename) = File::Temp::tempfile('apicert_XXXX', DIR => '/tmp', SUFFIX => '.pem', UNLINK => 0);
        print $tmpfh $data;
        close $tmpfh;
    }
    $ua->ssl_opts(
        SSL_cert_file => $tmpfilename,
        SSL_key_file => $tmpfilename,
    ) if $ua;
    return $tmpfilename;
}

sub clear_cert {
    my $self = shift;
    lock $tmpfilename;
    return $self unless $tmpfilename;
    unlink $tmpfilename;
    undef $tmpfilename;
    delete $self->{ssl_cert};
    delete $self->{ua};
    return $self;
}

sub ssl_auth_allowed {
    my $self = shift;
    my($role) = @_;
    if ($role eq 'admin' || $role eq 'default' || $role eq 'reseller') {
        return 1;
    }
    return 0;
}

sub runas {
    my $self = shift;
    my($role_in,$uri) = @_;
    my($user,$pass,$role,$realm,$port) = $self->get_role_credentials($role_in);
    my $base_url = $self->base_uri;
    $base_url =~ s/^(https?:[^:]+:)\d+(?:$|\/)/$1$port\//;
    #print Dumper ["base_url",$base_url,"role",$role,$user,$pass];
    $self->base_uri($base_url);
    $uri //= $self->base_uri;
    $uri =~ s/^https?:\/\/|\/$//g;
    #print Dumper ["runas",$uri, $realm, $user, $pass,"requested",$role_in,"old",$self->runas_role];
    if ($role_in ne $self->runas_role) {
        $self->clear_cert;
        $self->ua($self->_create_ua(0));
    }
    $self->ua->credentials( $uri, $realm, $user, $pass);
    $self->runas_role($role);
    $self->init_ssl_cert($self->ua, $role);
    diag("runas: $role;");
    return $self;
}

sub get_role_credentials{
    my $self = shift;
    my($role) = @_;
    my($user,$pass);
    $role //= $self->runas_role // 'default';
    my ($realm,$port);
    if($role eq 'default' || $role eq 'admin'){
        $user = $ENV{API_USER} // 'administrator';
        $pass = $ENV{API_PASS} // 'administrator';
        $realm = 'api_admin_http';
        $port = '1443';
    }elsif($role eq 'reseller'){
        $user = $self->reseller_admin_user // $ENV{API_USER_RESELLER} // 'api_test';
        $pass = $self->reseller_admin_pass // $ENV{API_PASS_RESELLER} // 'api_test';
        $realm = 'api_admin_http';
        $port = '1443';
    }elsif($role eq 'subscriber'){
        $user = $self->subscriber_user;
        $pass = $self->subscriber_pass;
        $realm = 'api_subscriber_http';
        $port = '443';
    }
    return($user,$pass,$role,$realm,$port);
}

sub set_subscriber_credentials{
    my($self,$data) = @_;
    $self->subscriber_user(join('@',@{$data}{qw/webusername domain/}));
    $self->subscriber_pass($data->{webpassword});
}

sub set_reseller_credentials{
    my($self,$data) = @_;
    $self->reseller_admin_user($data->{login});
    $self->reseller_admin_pass($data->{password});
}

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

sub get_id_from_created{
    my($self, $created_info) = @_;
    my $id = $self->get_id_from_location($created_info->{location});
    return $id;
}

sub get_id_from_location{
    my($self, $location) = @_;
    my $id = $location // '';
    $id=~s/.*?\D(\d+)$/$1/gis;
    return $id;
}

sub get_hal_name{
    my($self,$name) = @_;
    $name //= $self->name;
    return "ngcp:".$name;
}

sub restore_uri_custom{
    my($self) = @_;
    $self->URI_CUSTOM($self->URI_CUSTOM_STORE);
    $self->URI_CUSTOM_STORE(undef);
}

sub add_query_params{
    my($self, $query_params_add) = @_;
    my $query_params_old = $self->QUERY_PARAMS;
    $self->QUERY_PARAMS( $self->QUERY_PARAMS.( $self->QUERY_PARAMS ? '&' : '').$query_params_add);
    return $query_params_old;
}

sub get_uri_collection{
    my($self,$name) = @_;
    $name //= $self->name;
    return $self->normalize_uri("/api/".$name.($name ? "/" : "").($self->QUERY_PARAMS ? ( $self->QUERY_PARAMS !~/^\?/ ? "?" : "").$self->QUERY_PARAMS : ""));
}

sub get_uri_collection_paged{
    my($self,$name, $page, $rows) = @_;
    my $uri = $self->get_uri_collection($name);
    return $uri.($uri !~/\?/ ? '?':'&').'page='.($page // $self->PAGE // '1').'&rows='.($rows // $self->ROWS // '1').($self->NO_COUNT ? '&no_count=1' : '');
}

sub get_uri_get{
    my($self,$query_string, $name) = @_;
    $name //= $self->name;
    return $self->normalize_uri("/api/".$name.($query_string ? '/?' : '/' ).$query_string);
}

sub get_uri{
    my($self,$add,$name) = @_;
    $add //= '';
    $name //= $self->name;
    return $self->normalize_uri("/api/".$name.'/'.$add);
}

sub get_uri_item{
    my($self,$name,$item) = @_;
    my $resuri;
    $item ||= $self->get_item_hal($name);
    $resuri = $self->normalize_uri('/'.( $item->{location} // '' ));
    return $resuri;
}

sub get_item_hal{
    my($self, $name, $uri, $reload, $number) = @_;
    $name ||= $self->name;
    my $resitem ;
    #print Dumper ["get_item_hal","name",$name,"uri",$uri,$self->DATA_LOADED->{$name}];
    if(!$uri && !$reload){
        if(( $name eq $self->name ) && $self->DATA_CREATED->{FIRST}){
            $resitem = $self->get_created_first;
        }
        if(!$resitem && $self->DATA_LOADED->{$name} && @{$self->DATA_LOADED->{$name}}){
            $resitem = $self->DATA_LOADED->{$name}->[0];
        }
    }
    if(!$resitem){
        my ($reshal, $location,$total_count,$reshal_collection);
        $uri //= $self->get_uri_collection_paged($name);
        #print Dumper "get_item_hal: uri=$uri;";
        my($res,$list_collection,$req) = $self->check_item_get($self->normalize_uri($uri));
        ($reshal,$location,$total_count,$reshal_collection) = $self->get_hal_from_collection($list_collection,$name,$number);
        #print Dumper ["get_item_hal",$location,$total_count,$reshal,$reshal_collection];
        if($total_count || ('HASH' eq ref $reshal->{content} && $reshal->{content}->{total_count})){
            $self->IS_EMPTY_COLLECTION(0);
            $resitem = {
                num => 1,
                content => $reshal,
                res => $res,
                req => $req,
                location => $location,
                total_count => $total_count,
                content_collection => $reshal_collection,
            };
            $self->DATA_LOADED->{$name} ||= [];
            push @{$self->DATA_LOADED->{$name}}, $resitem;
        }else{
            $self->IS_EMPTY_COLLECTION(1);
        }
    }
    return $resitem;
}

sub get_hal_from_collection{
    my($self,$list_collection,$name,$number) = @_;
    $number //= 0;
    my $hal_name = $self->get_hal_name($name);
    my($reshal,$reshal_collection,$location,$total_count);
    $reshal_collection = $list_collection;
    if( $list_collection->{_embedded} && ref $list_collection->{_embedded}->{$hal_name} eq 'ARRAY') {
        #print Dumper ["get_hal_from_collection","1"];
        $reshal = $list_collection->{_embedded}->{$hal_name}->[$number];
        $location = $reshal->{_links}->{self}->{href};
        $total_count = $reshal->{total_count} // $list_collection->{total_count};
    } elsif( $list_collection->{_embedded} && ref $list_collection->{_embedded}->{$hal_name} eq 'HASH') {
        #print Dumper ["get_hal_from_collection","2"];
        $reshal = $list_collection->{_embedded}->{$hal_name};
        $location = $reshal->{_links}->{self}->{href};
        $total_count = $list_collection->{total_count};
        #todo: check all collections
    } elsif(ref $list_collection->{_links}->{$hal_name} eq "HASH") {
#found first subscriber
        #print Dumper ["get_hal_from_collection","3"];
        $reshal = $list_collection;
        $location = $reshal->{_links}->{$hal_name}->{href};
        $total_count = $reshal->{total_count};
    } elsif( ref $list_collection eq 'HASH' && $list_collection->{_links}->{self}->{href}) {
#preferencedefs collection
#or empty collection, see "/api/pbxdeviceprofiles/?name=two"
#or just got requested item, as /api/sibscribers/id
        $reshal = $list_collection;
        $location = $reshal->{_links}->{self}->{href};
        $total_count = $reshal->{total_count} // 1;
        #print Dumper ["get_hal_from_collection","4",$total_count];
    }
    return ($reshal,$location,$total_count,$reshal_collection);
}

sub get_collection_hal{
    my($self, $name, $uri, $reload, $page, $rows) = @_;
    my (@reshals, $location,$total_count,$reshal_collection,$rescollection,$firstitem,$res,$list_collection,$req);

    $name ||= $self->name;
    if(!$uri || $uri !~/rows=\d+/){
        if(!$rows){
            $firstitem = $self->get_item_hal($name, $uri, $reload);
            $rows = $total_count = $firstitem->{total_count};
        }
        if(!$rows){
            return;
        }
        $page ||= 1;
        $uri //= $self->get_uri_collection($name);
        $uri .= ( ($uri =~/\?/) ? '&' : '?')."page=$page&rows=$rows";
    }
    if(!$firstitem || ($page != 1 || $rows != 1)){
        ($res,$list_collection,$req) = $self->check_item_get($self->normalize_uri($uri));
        ($reshals[0],$location,$total_count,$reshal_collection) = $self->get_hal_from_collection($list_collection,$name);
    }else{
        #the only risk here is that we get reshal_collection as content_collection, although potentially they may differ.
        ($res,$list_collection,$req,$reshals[0],$location,$total_count,$reshal_collection) = @{$firstitem}{qw/res content_collection req content location total_count content_collection/};
    }
    #print Dumper ["get_collection_hal",$total_count];
    if($total_count){
        $self->IS_EMPTY_COLLECTION(0);
        #$self->DATA_LOADED->{$name} ||= [];
        $rescollection = {
            total_count => $total_count,
            content => $reshal_collection,
            res => $res,
            req => $req,
            collection => [],
        };
        my $add_item = sub{
            my ($number,$location) = @_;
            my $resitem = {
                num => $number,
                content => $reshals[$number],
                location => $location,
            };
            #while no caching here
            #push @{$self->DATA_LOADED->{$name}}, $resitem;
            push @{$rescollection->{collection}}, $resitem;
        };
        $add_item->(0);
        for(my $i=1; $i<$total_count; $i++){
            ($reshals[$i],$location) = $self->get_hal_from_collection($reshal_collection,$name,$i);
            $add_item->($i,$location);
        }
    }else{
        $self->IS_EMPTY_COLLECTION(1);
    }
    return $rescollection;
}

sub get_created_first{
    my($self) = @_;
    return $self->DATA_CREATED->{FIRST} ? $self->DATA_CREATED->{ALL}->{$self->DATA_CREATED->{FIRST}} : undef;
}

sub get_uri_current{
    my($self, $name) = @_;
    $self->URI_CUSTOM and return $self->URI_CUSTOM;
    return $self->get_uri_item($name);
}

sub encode_content{
    my($self, $content, $type) = @_;
    $type //= $self->ENCODE_CONTENT;
    my ($content_res,$content_type_res) = ($content, $type);
    my %json_types = (
        'application/json' => 1,
        'application/json-patch+json' => 1,
        'json' => 1,
    );
    #print Dumper ["encode_content.1",$content, $type] ;
    if($content){
        if('HASH' eq ref $content
            && $content->{json}
            && (('HASH' eq ref $content->{json}) || ( 'ARRAY' eq ref $content->{json} ) )
        ){
            $content->{json} = JSON::to_json($content->{json});
            $content_res = [
                %{$content},
            ];
            $content_type_res = 'multipart/form-data';
        }elsif( $json_types{$type} && (('HASH' eq ref $content) ||('ARRAY' eq ref $content))  ){
            #print Dumper $content;
            my $json = JSON->new->allow_nonref;
            $content_res = $json->encode($content);
            $type eq 'json' and $content_type_res = 'application/json';
        }
    }
    #print Dumper ["encode_content.2",$content_res,$content_type_res] ;
    return ($content_res,$content_type_res);
}

sub request{
    my($self,$req) = @_;

    if($self->DEBUG){
        my $credentials = {};
        (@$credentials{qw/user password/},undef,undef) = $self->get_role_credentials();
        my $curl = Test::HTTPRequestAsCurl::as_curl($req, credentials => $credentials );
        print $req->as_string;
        print "$curl\n\n";
    }
    if(!$self->DEBUG_ONLY){
        $self->init_ssl_cert($self->ua, $self->runas_role);
        my $request_time = time;
        my $res = $self->ua->request($req);
        $request_time = time() - $request_time;
        push @$requests_time, { response => $res, time => $request_time };
        diag(sprintf($self->name_prefix."request:%s: %s", $req->method, $req->uri));
        #draft of the debug mode
        if(1 && $self->DEBUG){
            if($res->code >= 400){
                print longmess();
                print Dumper $req;
                print Dumper $res;
                print Dumper $self->get_response_content($res);
                #die;
            }
        }
        return $res;
    }
}

sub request_process{
    my($self,$req) = @_;
    #print $req->as_string;
    my $res = $self->request($req);
    my $rescontent = $self->get_response_content($res);
    return ($res,$rescontent,$req);
}

sub get_request_get{
    my($self, $uri, $headers) = @_;
    $headers ||= {};
    $uri = $self->normalize_uri($uri);
    my $req = HTTP::Request->new('GET', $uri);
    foreach my $key (keys %$headers){
        $req->header($key => $headers->{$key});
    }
    return $req ;
}

sub get_request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    $uri = $self->normalize_uri($uri);
    #This is for multipart/form-data cases
    my $content_type;
    ($content,$content_type) = $self->encode_content($content, $self->content_type->{PUT});
    my $req = POST $uri,
        Content_Type => $content_type,
        $content ? ( Content => $content ) : ();
    $req->method('PUT');
    $req->header('Prefer' => 'return=representation');
    return $req;
}

sub get_request_patch{
    my($self,$uri,$content) = @_;
    $uri ||= $self->get_uri_current;
    my $content_type;
    ($content,$content_type) = $self->encode_content($content, $self->content_type->{PATCH});
    my $req = HTTP::Request->new('PATCH', $uri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => $content_type );
    $content and $req->content($content);
    return $req;
}

sub get_request_post{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    $uri = $self->normalize_uri($uri);
    #This is for multipart/form-data cases
    my $content_type;
    ($content,$content_type) = $self->encode_content($content, $self->content_type->{POST});
    my $req = POST $uri,
        Content_Type => $content_type,
        $content ? ( Content => $content ) : ();
    $req->header('Prefer' => 'return=representation');
    return $req;
}

sub request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    my $req = $self->get_request_put( $content, $self->normalize_uri($uri) );
    diag("request_put: uri: ".$req->uri.";");
    diag("request_put: content: ".$req->content.";");
    diag("request_put: content_type: ".$req->header('Content-Type').";");
    my $res = $self->request($req);
    if($res){
        my $rescontent = $self->get_response_content($res);
        return wantarray ? ($res,$rescontent,$req) : $res;
    }
}

sub request_patch{
    my($self,$content, $uri, $req) = @_;
    $uri ||= $self->get_uri_current;
    #patch is always a json
    $req ||= $self->get_request_patch( $self->normalize_uri($uri), $content);
    diag("request_patch: uri: ".$req->uri.";");
    diag("request_patch: content: ".$req->content.";");
    diag("request_patch: content_type: ".$req->header('Content-Type').";");
    my $res = $self->request($req);
    if($res){
        my $rescontent = $self->get_response_content($res);
        #print Dumper [$res,$rescontent,$req];
        return wantarray ? ($res,$rescontent,$req) : $res;
    }
}

sub request_post{
    my($self, $content, $uri, $req) = @_;
    if(!$req){
        $uri ||= $self->get_uri_collection;
        $uri = $self->normalize_uri($uri);
        my $content_type;
        ($content,$content_type) = $self->encode_content($content, $self->content_type->{POST});
        #form-data is set automatically, despite on $self->content_type->{POST}
        $req ||= POST $uri,
            Content_Type => $content_type,
            Content => $content;
        $req->header('Prefer' => 'return=representation');
    }
    diag("request_post: uri: ".$req->uri.";");
    diag("request_post: content: ".$req->content.";");
    diag("request_post: content_type: ".$req->header('Content-Type').";");
    my $res = $self->request($req);
    my $rescontent = $self->get_response_content($res);
    my $location = $res->header('Location') // '';
    my $additional_info = { id => $self->get_id_from_location($location) // '' };
    return wantarray ? ($res,$rescontent,$req,$content,$additional_info) : $res;
};

sub request_options{
    my ($self,$uri) = @_;
    # OPTIONS tests
    my $req = HTTP::Request->new('OPTIONS', $self->normalize_uri($uri));
    my $res = $self->request($req);
    my $content = $self->get_response_content($res);
    return($res,$content,$req);
}

sub request_delete{
    my ($self,$uri) = @_;
    # DELETE tests
    #no auto rows for deletion
    my $name = $self->name // '';
    my $del_uri = $self->normalize_uri($uri);
    my $req = HTTP::Request->new('DELETE', $del_uri);
    my $res = $self->request($req);
    if($res->code == 404){
    #todo: if fake data will provide tree of the cascade deletion - it can be checked here, I think
        diag($name.": Item $del_uri is absent already.");
    }elsif($res->code == 423){
    #todo: if fake data will provide tree of the cascade deletion - it can be checked here, I think
        diag($name.": Item '$del_uri' can't be deleted.");
    }elsif(!$self->QUIET_DELETION){
        $self->http_code_msg(204, "$name: check response from DELETE $uri", $res);
    }elsif($res->code == 204){
        diag($name.": Item $del_uri deleted.");
    }
    my $content = $self->get_response_content($res);
    if($self->cache_data){
        #my $restored = (-e $self->data_cache_file) ? retrieve($self->data_cache_file) : {};
        #if('204' eq $res->code){
        #    $restored->{deleted}->{204}->{$uri} = 1;
        #}
        #$restored->{deleted}->{all}->{$uri} = [$res->code,$res->message];
        #store $restored, $self->data_cache_file;
        $self->replace_cached_data(sub{
            my $restored = shift;
            if('204' eq $res->code){
                $restored->{deleted}->{204}->{$uri} = 1;
            }
            $restored->{deleted}->{all}->{$uri} = [$res->code,$res->message];
        });
    }
    return($req,$res,$content);
}

sub request_get{
    my($self,$uri,$req,$headers) = @_;
    if (!$req) {
        $uri = $self->normalize_uri($uri);
        $req //= $self->get_request_get($uri,$headers);    
    }
    my $res = $self->request($req);
    my $content = $self->get_response_content($res);
    return wantarray ? ($res, $content, $req) : $res;
}

sub get_response_content{
    my($self,$res) = @_;
    my $content = '';
    if($res->decoded_content){
        eval { $content = JSON::from_json($res->decoded_content); };
    }
    #print "get_response_content;\n";
    #print Dumper [caller];
    #print Dumper $content;
    return $content;
}

sub normalize_uri{
    my($self,$uri) = @_;
    $uri ||= $self->get_uri_current // '';
    if($uri !~/^http/i){
        $uri = $self->base_uri.$uri;
    }
    return $uri;
}
############## end of test machine
############## start of test collection

#---------------- options, methods, hal format

sub check_options_collection{
    my ($self, $uri) = @_;
    # OPTIONS tests
    $uri //= $self->get_uri_collection;
    my $req = HTTP::Request->new('OPTIONS', $uri );
    my $res = $self->request($req);
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-".$self->name, "$self->{name}: check Accept-Post header in options response");
    $self->check_methods($res,'collection');
}

sub check_options_item{
    my ($self,$uri) = @_;
    # OPTIONS tests
    $uri ||= $self->get_uri_current;
    if(!$self->IS_EMPTY_COLLECTION){
        my $req = HTTP::Request->new('OPTIONS', $uri);
        my $res = $self->request($req);
        $self->check_methods($res,'item');
    }
}

sub check_methods{
    my($self, $res, $area) = @_;
    my $opts = $self->get_response_content($res);
    $self->http_code_msg(200, "check $area options request", $res,$opts);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "$self->{name}: check for valid 'methods' in body");
    foreach my $opt(keys %{$self->methods->{$area}->{all}} ) {
        if(exists $self->methods->{$area}->{allowed}->{$opt}){
            ok((grep { /^$opt$/ } @hopts), "$self->{name}: check for existence of '$opt' in Allow header");
            ok((grep { /^$opt$/ } @{ $opts->{methods} }), "$self->{name}: check for existence of '$opt' in body");
        }else{
            ok((!grep { /^$opt$/ } @hopts), "$self->{name}: check for absence of '$opt' in Allow header");
            ok((!grep { /^$opt$/ } @{ $opts->{methods} }), "$self->{name}: check for absence of '$opt' in body");
        }
    }
}

sub check_list_collection{
    my($self, $check_embedded_cb) = @_;
    my $nexturi = $self->get_uri_collection_paged;
    my @href = ();
    my $test_info_prefix = "$self->{name}: check_list_collection: ";
    my $page = 1;
    my $next_page;
    my $rows_old = $self->ROWS;
    if ($self->NO_COUNT && $self->CHECK_LIST_LIMIT) {
        $self->NO_COUNT(0);
        diag("get total_count before no_count check;ROWS=".$self->ROWS);
        my $collection_info = $self->get_collection_hal($self->name, undef, 1, 1, 1);
        diag("got total_count for no_count check: ".(defined $collection_info->{total_count} ? $collection_info->{total_count} : "undef").";");
        $self->NO_COUNT(1);
        my $rows_candidate = int($collection_info->{total_count} / ( $self->CHECK_LIST_LIMIT ));
        $rows_candidate = $rows_candidate ? $rows_candidate : 1;
        $self->ROWS($rows_candidate);
    }
    do {
        #print "nexturi=$nexturi;\n";
        my ($res,$list_collection) = $self->check_item_get($nexturi);
        my $selfuri = $self->normalize_uri($list_collection->{_links}->{self}->{href});
        my $sub_sort_params = sub {my $str = $_[0]; return (substr $str, 0, (index $str, '?') + 1) . join('&', sort split /&/, substr  $str, ((index $str, '?') + 1))};
        $selfuri = $sub_sort_params->($selfuri);
        $nexturi = $sub_sort_params->($nexturi);
        is($selfuri, $nexturi, $test_info_prefix."check _links.self.href of collection");
        my $colluri = URI->new($selfuri);
        if(
            (!$self->NO_COUNT) 
            && (
                ( $list_collection->{total_count} && is_int($list_collection->{total_count}) && $list_collection->{total_count} > 0 ) 
                || !$self->ALLOW_EMPTY_COLLECTION)){
            ok($list_collection->{total_count} > 0, $test_info_prefix."check 'total_count' of collection");
        }

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, $test_info_prefix."check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        ok($rows != 0, $test_info_prefix."check existence of the 'rows'");
        if($page == 1) {
            ok(!exists $list_collection->{_links}->{prev}->{href}, $test_info_prefix."check absence of 'prev' on first page");
        } else {
            ok(exists $list_collection->{_links}->{prev}->{href}, $test_info_prefix."check existence of 'prev'");
        }
        if (!$self->NO_COUNT) {
            if(($rows != 0) && ($list_collection->{total_count} / $rows) <= $page) {
                ok(!exists $list_collection->{_links}->{next}->{href}, $test_info_prefix."check absence of 'next' on last page");
            } else {
                ok(exists $list_collection->{_links}->{next}->{href}, $test_info_prefix."check existence of 'next'");
            }
        }

        if($list_collection->{_links}->{next}->{href}) {
            if ( !$self->CHECK_LIST_LIMIT ) {
                $nexturi = $self->normalize_uri($list_collection->{_links}->{next}->{href});
            } else {
                if ($self->NO_COUNT) {
                    #we have no total_count
                    $next_page = $page + 1;
                } else {
                    my $rows_increment = int($list_collection->{total_count} / ( $self->CHECK_LIST_LIMIT * ($self->ROWS ? $self->ROWS  : 1 ) ));
                    $rows_increment = $rows_increment ? $rows_increment : 1;
                    $next_page = $page + $rows_increment;
                    if ($next_page > $list_collection->{total_count} ) {
                        $next_page = $list_collection->{total_count};
                    }
                }
                $nexturi = $self->get_uri_collection_paged(undef,  $next_page);
            }
        } else {
            $nexturi = undef;
        }

        my $hal_name = $self->get_hal_name;
        if((!$self->NO_COUNT) 
            && (
                ($list_collection->{total_count} && is_int($list_collection->{total_count}) && $list_collection->{total_count} > 0 ) 
                || !$self->ALLOW_EMPTY_COLLECTION) ){
            if (! ok(((ref $list_collection->{_links}->{$hal_name} eq "ARRAY" ) ||
                (ref $list_collection->{_links}->{$hal_name} eq "HASH" ) ), $test_info_prefix."check if 'ngcp:".$self->name."' is array/hash-ref")) {
                    diag($list_collection->{_links}->{$hal_name});
                }
        }


        # it is really strange - we check that the only element of the _links will be hash - and after this treat _embedded as hash too
        #the only thing that saves us - we really will not get into the if ever
        if(ref $list_collection->{_links}->{$hal_name} eq "HASH") {
            $self->check_embedded($list_collection->{_embedded}->{$hal_name}, $check_embedded_cb);
            push @href, $list_collection->{_links}->{$hal_name}->{href};
        } else {
            foreach my $item_c(@{ $list_collection->{_links}->{$hal_name} }) {
                push @href, $item_c->{href};
            }
            foreach my $item_c(@{ $list_collection->{_embedded}->{$hal_name} }) {
            # these relations are only there if we have zones/fees, which is not the case with an empty model
                $self->check_embedded($item_c, $check_embedded_cb);
                push @href, $item_c->{_links}->{self}->{href};
            }
        }
        $page = $next_page;
    } while($nexturi);
    $self->ROWS($rows_old);
    return \@href;
}

sub check_get2order_by{
    my($self, $name, $uri, $params) = @_;

    $uri //= $self->get_uri_item($name);
    diag($self->name.": check_get2order_by:");

    $name //= $self->name;
    $params //= {};
    $params->{ignore_fields} //= [];
    my $ignore_fields = { map { $_ => 1 } $params->{ignore_fields}};
    my $item = {};
    my $response;
    (undef,$item->{content}) = $self->check_item_get($uri);
    if (ref $item->{content} ne 'HASH') {
        diag($self->name.": check_get2order_by: not hash reference:");
        diag(Dumper($item->{content}));
        #we will not check if empty collection is allowed here. If necessary, we will take other place for this
        return;
    }

    while (my ($path, $value) = each %{$item->{content}} ) {
        if ($path ne '_links' && $path ne 'total_count' &&  !exists $ignore_fields->{$path}) {
            my $query_params_old = $self->QUERY_PARAMS;
            foreach my $order_by_query_params ('order_by='.$path, 'order_by='.$path.'&order_by_direction=desc', 'order_by='.$path.'&order_by_direction=asc') {
                $self->add_query_params($order_by_query_params);
                $uri = $self->get_uri_collection_paged($name);
                $self->get_collection_hal( $name, $uri, 1 );
                $self->QUERY_PARAMS($query_params_old);
            }
        }
    }
}

sub check_created_listed{
    my($self,$listed) = @_;
    my $created_items = clone($self->DATA_CREATED->{ALL});
    if(!$created_items || ref $created_items ne 'ARRAY' || !scalar @$created_items) {
        return;
    }
    ok($self->EXPECTED_AMOUNT_CREATED == scalar(keys %{$created_items}), "$self->{name}: check amount of created items");
    if( $self->CHECK_LIST_LIMIT ) {
        #we didn't load all collections into $listed, as we requested just limited pages, 
        #so we can't check if all created are really listed
        #let's try to get them just as latest items from the collection
        my $query_params_old = $self->add_query_params('order_by=id&order_by_direction=desc');
        my $uri = $self->get_uri_collection_paged($self->name, 1, $self->EXPECTED_AMOUNT_CREATED);
        my $collection_hals = $self->get_collection_hal($self->name,$uri);
        $listed = [map {$_->{location}} @{$collection_hals->{collection}}];
    }
    $listed //= [];#to avoid error about not array reference
    $created_items //= [];
    foreach (@$listed){
        delete $created_items->{$_};
    }
    is(scalar(keys %{$created_items}), 0, "$self->{name}: check if all created test items have been found in the list");
    if(scalar(keys %{$created_items})){
        #print Dumper $created_items;
        #print Dumper $listed;
    }
}

sub check_embedded {
    my($self, $embedded, $check_embedded_cb) = @_;
    defined $check_embedded_cb and $check_embedded_cb->($embedded);
    foreach my $embedded_name(@{$self->embedded_resources}){
        if(ref $embedded eq "ARRAY") {
            foreach my $emb(@{ $embedded }) {
                ok(exists $emb->{_links}->{'ngcp:'.$embedded_name}, "$self->{name}: check presence of ngcp:$embedded_name relation");
            }
        } else {
            ok(exists $embedded->{_links}->{'ngcp:'.$embedded_name}, "$self->{name}: check presence of ngcp:$embedded_name relation");
        }
    }
}

#------------------- put bundle -----------

#------------------- put bundle -----------

sub check_put_content_type_empty{
    my($self) = @_;
    # check if it fails without content type
    my $req = $self->get_request_put;
    $req->remove_header('Content-Type');
    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=minimal");
    my($res,$content) = $self->request_process($req);
    $self->http_code_msg(415, "check put missing content type", $res, $content);
}

sub check_put_content_type_wrong{
    my($self) = @_;
    # check if it fails with unsupported content type
    my $req = $self->get_request_put;
    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/xxx');
    my($res,$content) = $self->request_process($req);
    $self->http_code_msg(415, "check put invalid content type", $res, $content);
}

sub check_put_prefer_wrong{
    my($self) = @_;
    # check if it fails with invalid Prefer
    my $req = $self->get_request_put;
    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=invalid");
    my($res,$content) = $self->request_process($req);
    $self->http_code_msg(400, "check put invalid prefer", $res, $content, "Header 'Prefer' must be either 'return=minimal' or 'return=representation'.");
}

sub check_put_body_empty{
    my($self) = @_;
    # check if it fails with missing body
    my $req = $self->get_request_put;
    #$req->remove_header('Prefer');
    #$req->header('Prefer' => "return=representation");
    my($res,$content) = $self->request_process($req);
    $self->http_code_msg(400, "check put no body", $res, $content);
}

sub check_put_bundle{
    my($self) = @_;
    $self->check_put_content_type_empty;
    $self->check_put_content_type_wrong;
    #$self->check_put_prefer_wrong;
    $self->check_put_body_empty;
}

#-------------------- patch bundle -------
sub check_patch_correct{
    my($self,$content) = @_;
    my ($res,$rescontent,$req) = $self->request_patch( $content );
    $self->http_code_msg(200, "check patched item", $res, $rescontent);
    is($rescontent->{_links}->{self}->{href}, $self->uri2location($req->uri), "$self->{name}: check patched self link");
    is($rescontent->{_links}->{collection}->{href}, '/api/'.$self->name.'/', "$self->{name}: check patched collection link");
    return ($res,$rescontent,$req);
}

sub check_patch_prefer_wrong{
    my($self) = @_;
    my $req = $self->get_request_patch;
    $req->remove_header('Prefer');
    $req->header('Prefer' => 'return=minimal');
    my ($res,$content) = $self->request_process($req);
    $self->http_code_msg(415, "check patch invalid prefer", $res, $content);
}

sub check_patch_content_type_empty{
    my($self) = @_;
    my $req = $self->get_request_patch;
    $req->remove_header('Content-Type');
    my ($res,$content) = $self->request_process($req);
    $self->http_code_msg(415, "check patch missing media type", $res, $content);
}

sub check_patch_content_type_wrong{
    my($self) = @_;
    my $req = $self->get_request_patch;
    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/xxx');
    my($res,$content) = $self->request_process($req);
    $self->http_code_msg(415, "check patch invalid media type", $res, $content);
}

sub check_patch_body_empty{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch;
    $self->http_code_msg(400, "check patch missing body", $res, $content);
    like($content->{message}, qr/is missing a message body/, "$self->{name}: check patch missing body response");
}

sub check_patch_body_notarray{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        { foo => 'bar' },
    );
    $self->http_code_msg(400, "check patch no array body", $res, $content);
    like($content->{message}, qr/must be an array/, "$self->{name}: check patch missing body response");
}

sub check_patch_op_missed{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ foo => 'bar' }],
    );
    $self->http_code_msg(400, "check patch no op in body", $res, $content);
    like($content->{message}, qr/must have an 'op' field/, "$self->{name}: check patch no op in body response");
}

sub check_patch_op_wrong{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'bar' }],
    );
    $self->http_code_msg(400, "check patch invalid op in body", $res, $content);
    like($content->{message}, qr/Invalid PATCH op /, "$self->{name}: check patch no op in body response");
}

sub check_patch_opreplace_paramsmiss{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'replace' }],
    );
    $self->http_code_msg(400, "check patch missing fields for op", $res, $content);
    like($content->{message}, qr/Missing PATCH keys /, "$self->{name}: check patch missing fields for op response");
}

sub check_patch_opreplace_paramsextra{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'replace', path => '/foo', value => 'bar', invalid => 'sna' }],
    );
    $self->http_code_msg(400, "check patch extra fields for op", $res, $content);
    like($content->{message}, qr/Invalid PATCH key /, "$self->{name}: check patch extra fields for op response");
}

sub check_patch_path_wrong{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [ { op => 'replace', path => '/some/path', value => 'invalid' } ],
    );
    $self->http_code_msg(422, "check patched invalid path", $res, $content);
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
    $self->check_patch_path_wrong;
}


sub check_bundle{
    my($self) = @_;
    $self->check_options_collection();
    # iterate over collection to check next/prev links and status
    my $listed=[];
    if($self->methods->{collection}->{allowed}->{GET}){
        $listed = $self->check_list_collection();
        $self->check_created_listed($listed);
        if (!$self->NO_TEST_NO_COUNT) {
            $self->NO_COUNT('1');
            $self->check_list_collection();
            $self->NO_COUNT('');
        }
        $self->check_get2order_by();
        #TODO: the same for allowed query params. All query_params that have
        #the same field in the item can be tested. Also if some simple map can be applied - let it be applied
        #all untested query_params should be shown in statistic
    }
    # test model item
    if(@$listed && !$self->NO_ITEM_MODULE){
        $self->check_options_item;
        if(!$self->IS_EMPTY_COLLECTION){
            if(exists $self->methods->{'item'}->{allowed}->{'PUT'}){
                $self->check_put_bundle;
            }
            if(exists $self->methods->{'item'}->{allowed}->{'PATCH'}){
                $self->check_patch_bundle;
            }
        }
    }
}

sub check_item_get{
    my($self, $uri, $msg, $name) = @_;
    $msg //= '';
    $uri ||= $self->get_uri_current($name);
    $uri = $self->normalize_uri($uri);
    my ($res, $content, $req) = $self->request_get($uri);
    $self->http_code_msg(200, $msg.($msg?": ":"")."fetch uri: $uri", $res);
    return wantarray ? ($res, $content, $req) : $res;
}

sub process_data{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $data = $data_in || clone($self->DATA_ITEM);
    if(defined $data_cb && 'CODE' eq ref $data_cb){
        $data_cb->($data, $data_cb_data, $self);
    }
    return $data;
}

sub check_item_post{
    my($self, $data_cb, $data_in, $data_cb_data, $uri) = @_;
    my $data = $self->process_data($data_cb, $data_in, $data_cb_data);
    #print Dumper $data;
    my ($res,$rescontent,$req) = $self->request_post($data, $uri);#,$uri,$req
    return wantarray ? ($res,$rescontent,$req,$data) : $res;
}

sub check_item_delete{
    my($self, $uri, $msg) = @_;
    my $name = $self->name // '';
    $uri =  $self->normalize_uri($uri);
    if($name eq $self->name) {
        $self->EXPECTED_AMOUNT_CREATED($self->EXPECTED_AMOUNT_CREATED - 1);
    }
    my ($req,$res,$content) = $self->request_delete($uri);#,$uri,$req
    $self->http_code_msg(204, "$name: check delete item $uri",$res,$content);
    return ($req,$res,$content);
}

sub check_create_correct{
    my($self, $number, $uniquizer_cb, $data_in) = @_;
    if(!$self->KEEP_CREATED){
        $self->clear_data_created;
    }
    $self->EXPECTED_AMOUNT_CREATED($self->EXPECTED_AMOUNT_CREATED + $number);
    $self->EXPECTED_AMOUNT_CREATED(int($self->EXPECTED_AMOUNT_CREATED + $number));
    $self->DATA_CREATED->{ALL} //= {};
    my @created = ();
    for(my $i = 1; $i <= $number; ++$i) {
        my $created_info={};
        my ($res, $content, $req, $content_post) = $self->check_item_post( $uniquizer_cb , $data_in, { i => $i } );
        my $location = $res->header('Location');
        if(exists $self->methods->{'item'}->{allowed}->{'GET'}){
            $self->http_code_msg(201, "create test item '".$self->name."' $i. Location: ".($location // ''),$res,$content);
        }else{
            $self->http_code_msg(200, "create test item '".$self->name."' $i. Location: ".($location // ''),$res,$content);
        }
        if($location){
            #some interfaces (e.g. subscribers) don't provide hal after creation - is it correct, by the way?
            my $get ={};
            if(!$content && exists $self->methods->{'item'}->{allowed}->{'GET'}){
                @$get{qw/res_get content_get req_get/} = $self->check_item_get($location,"no object returned after POST");
            }
            $created_info = {
                num => $i,
                content => $content ? $content : ($get->{content_get} // {}),
                res => $res,
                req => $req,
                location => $location,
                content_post => $content_post,
                %$get,
            };
            push @created, $created_info;
            $self->DATA_CREATED->{ALL}->{$location} = $created_info;
            $self->DATA_CREATED->{FIRST} = $location unless $self->DATA_CREATED->{FIRST};
        }
    }
    return \@created;
}

sub clear_test_data_all{
    my($self,$uri,$strict) = @_;
    my $name = $self->name // '';
    my @uris = $uri ? (('ARRAY' eq ref $uri) ? @$uri : ($uri)) : keys %{ $self->DATA_CREATED->{ALL} };
    foreach my $del_uri(@uris){
        $del_uri = $self->normalize_uri($del_uri);
        my($req,$res,$content);
        if($strict){#for particular deletion test
            ($req,$res,$content) = $self->check_item_delete($del_uri);
        }else{
            ($req,$res,$content) = $self->request_delete($del_uri);
        }
    }
    $self->clear_data_created();
    return \@uris;
}

sub clear_test_data_dependent{
    my($self,$uri,$strict) = @_;
    my $name = $self->name // '';
    my $del_uri = $self->normalize_uri($uri);
    my($req,$res,$content);
    if($strict){#for particular deletion test
        ($req,$res,$content) = $self->check_item_delete($del_uri);
    }else{
        ($req,$res,$content) = $self->request_delete($del_uri);
    }
    return ('204' eq $res->code);
}

sub check_get2put{
    my($self, $put_in, $get_in, $params) = @_;

    my($put_out,$get_out);

    $params //= {};
    $get_in //= {};
    $put_in //= {};

    $put_in->{uri} //= $put_in->{location};
    $get_in->{uri} //= $put_in->{uri};
    $put_in->{uri} //= $get_in->{uri};

    $get_in->{ignore_fields} //= [];
    $put_in->{ignore_fields} //= [];
    $params->{ignore_fields} //= [];
    my $ignore_fields = [@{$params->{ignore_fields}}, @{$get_in->{ignore_fields}}, @{$put_in->{ignore_fields}}];
    delete $get_in->{ignore_fields};
    delete $put_in->{ignore_fields};

    @$get_out{qw/response content request/} = $self->check_item_get($get_in->{uri});
    $put_out->{content_in} = clone($get_out->{content});
    delete $put_out->{content_in}->{_links};
    delete $put_out->{content_in}->{_embedded};
    # check if put is ok
    $put_out->{content_in} = $self->process_data($put_in->{data_cb}, $put_out->{content_in});
    #we are going to use created or loaded item - lets take it to redefine it's uri if will be necessary after put
    @{$put_out}{qw/response content request/} = $self->request_put( $put_out->{content_in}, $put_in->{uri} );
    foreach my $field (@{$ignore_fields}){
        delete $get_out->{content}->{$field};
        delete $put_out->{content}->{$field};
    }
    $self->http_code_msg(200, "check_get2put: check put successful", $put_out->{response},  $put_out->{content} );
    if (!is_deeply($get_out->{content}, $put_out->{content}, "$self->{name}: check_get2put: check put if unmodified put returns the same")) {
        diag(Dumper([$put_out->{content},$get_out->{content}]));
    }
    if ($put_out->{response}->header('Location') && ! $put_in->{uri} ) {
        my $default_item = $self->get_item_hal($self->name);
       $default_item->{location} = $put_out->{response}->header('Location');
    }
    return ($put_out,$get_out);
}

sub check_put2get{
    my($self, $put_in, $get_in, $params) = @_;

    my($put_out,$get_out);

    $params //= {};
    $get_in //= {};
    $put_in->{uri} //= $put_in->{location};
    $get_in->{uri} //= $put_in->{uri};
    $put_in->{uri} //= $get_in->{uri};
    $get_out->{uri} = $get_in->{uri};

    $get_in->{ignore_fields} //= [];
    $put_in->{ignore_fields} //= [];
    $params->{ignore_fields} //= [];
    my $ignore_fields = [@{$params->{ignore_fields}}, @{$get_in->{ignore_fields}}, @{$put_in->{ignore_fields}}];
    delete $get_in->{ignore_fields};
    delete $put_in->{ignore_fields};

    $put_in->{data_in} //=  $put_in->{content};
    $put_out->{content_in} = $self->process_data($put_in->{data_cb}, $put_in->{data_in});

    @{$put_out}{qw/response content request/} = $self->request_put( $put_out->{content_in}, $put_in->{uri} );
    $self->http_code_msg(200, "check_put2get: check put successful",$put_out->{response}, $put_out->{content});

    @{$get_out}{qw/response content request/} = $self->check_item_get($get_out->{uri});
    delete $get_out->{content}->{_links};
    delete $get_out->{content}->{_embedded};
    delete $put_out->{content_in}->{_links};
    delete $put_out->{content_in}->{_embedded};
    my $item_id = delete $get_out->{content}->{id};
    my $item_id_in = delete $put_out->{content_in}->{id};
    foreach my $field (@{$ignore_fields}){
        delete $get_out->{content}->{$field};
        delete $put_out->{content_in}->{$field};
    }
    if('CODE' eq ref $params->{compare_cb}){
        $params->{compare_cb}->($put_out,$get_out);
    }
    if(!$params->{skip_compare}){
        is_deeply($get_out->{content}, $put_out->{content_in}, "$self->{name}: check_put2get: check PUTed item against GETed item");
    }
    $get_out->{content}->{id} = $item_id;
    $put_out->{content_in}->{id} = $item_id_in;
    return ($put_out,$get_out);
}

sub check_patch2get{
    my($self, $patch_in, $get_in, $params) = @_;

    my($patch_out, $get_out, $get_uri, $patch_uri);

    $params //= {};
    $get_in //= {};
    $patch_in //= {};
    $patch_uri //= $patch_in->{location} if ref $patch_in eq 'HASH';
    $get_uri //= $patch_uri;
    $get_uri = $get_in if !ref $get_in;
    $get_uri //= $get_in->{location} if ref $get_in eq 'HASH';
    $patch_uri //= $get_uri;
    $get_out->{uri} = $get_uri;

    my $get_ignore_fields;
    $get_ignore_fields = $get_in->{ignore_fields} if ref $get_in eq 'HASH';
    $get_ignore_fields //= [];
    my $patch_ignore_fields;
    $patch_ignore_fields = $patch_in->{ignore_fields} if ref $patch_in eq 'HASH';
    $patch_ignore_fields //= [];
    $params->{ignore_fields} //= [];
    my $ignore_fields = [@{$params->{ignore_fields}}, @{$get_ignore_fields}, @{$patch_ignore_fields}];
    delete $get_in->{ignore_fields} if ref $get_in eq 'HASH';
    delete $patch_in->{ignore_fields} if ref $patch_in eq 'HASH';

    my $patch_exclude_fields = $params->{patch_exclude_fields} // {};
    if (ref $patch_exclude_fields eq 'ARRAY') {
        $patch_exclude_fields = {map {$_ => 1} @$patch_exclude_fields};
    }

    (undef, $patch_out->{content_before}) = $self->check_item_get( $patch_uri );

    my @patches;
    while (my ($path, $value) = each %{$patch_out->{content_before}} ) {
        if ($path ne 'id' && $path ne '_links' && !exists $patch_exclude_fields->{$path}) {
            push @patches, {'op' => 'replace', 'path' => '/'.$path, 'value' => $value};
        }
    }

    $patch_out->{content_in} = ref $patch_in eq 'HASH' && $patch_in->{content} 
        ? $patch_in->{content}
        : ref $patch_in eq 'ARRAY'
            ? $patch_in
            : [@patches]
        ;

    $patch_out->{content_patched} = Test::ApplyPatch::apply_patch(clone($patch_out->{content_before}),$patch_out->{content_in});
    @{$patch_out}{qw/response content request/} = $self->request_patch( $patch_out->{content_in}, $patch_uri );
    $self->http_code_msg(200, "check_patch2get: check patch successful",$patch_out->{response}, $patch_out->{content});
    
    #print Dumper $patch_out;

    @{$get_out}{qw/response content request/} = $self->check_item_get($get_out->{uri});
    delete $patch_out->{content_patched}->{_links};
    delete $patch_out->{content_patched}->{_links};
    delete $get_out->{content}->{_links};
    delete $get_out->{content}->{_embedded};
    my $item_id = delete $get_out->{content}->{id};
    my $item_id_in = delete$patch_out->{content_patched}->{id};
    foreach my $field (@{$ignore_fields}){
        delete $get_out->{content}->{$field};
        delete $patch_out->{content_patched}->{$field};
    }
    if('CODE' eq ref $params->{compare_cb}){
        $params->{compare_cb}->($patch_out,$get_out);
    }
    if(!$params->{skip_compare}){
        is_deeply($get_out->{content}, $patch_out->{content_patched}, "$self->{name}: check_patch2get: check PATCHed item against GETed item");
    }
    $get_out->{content}->{id} = $item_id;
    $patch_out->{content_patched}->{id} = $item_id_in;
    return ($patch_out,$get_out);
}

sub check_post2get{
    my($self, $post_in, $get_in, $params) = @_;
    $get_in //= {};
    #$post = {data_in=>,data_cb=>};
    #$get = {uri=>}
    #return
    #$post={response,content,request,data,location}
    #$get=={response,content,request,uri}

    $get_in->{ignore_fields} //= [];
    $post_in->{ignore_fields} //= [];
    $params->{ignore_fields} //= [];
    my $ignore_fields = [@{$params->{ignore_fields}}, @{$get_in->{ignore_fields}}, @{$post_in->{ignore_fields}}];
    delete $get_in->{ignore_fields};
    delete $post_in->{ignore_fields};



    my($post_out,$get_out);
    @{$post_out}{qw/response content request data/} = $self->check_item_post( $post_in->{data_cb}, $post_in->{data_in} );
    $self->http_code_msg(201, "check_post2get: POST item '".$self->name."' for check_post2get", @{$post_out}{qw/response content/});
    $post_out->{location} = $self->normalize_uri(($post_out->{response}->header('Location') // ''));

    $get_out->{uri} = $get_in->{uri} // $post_out->{location};
    @{$get_out}{qw/response content request/} = $self->check_item_get( $get_out->{uri}, "check_post2get: fetch POSTed test '".$self->name."'" );

    delete $get_out->{content}->{_links};
    my $item_id = delete $get_out->{content}->{id};
    foreach my $field (@$ignore_fields){
        delete $get_out->{content}->{$field};
        delete $post_out->{data}->{$field};
    }
    if('CODE' eq ref $params->{compare_cb}){
        $params->{compare_cb}->($post_out->{data}, $get_out->{content});
    }
    if(!$params->{skip_compare}){
        is_deeply($post_out->{data}, $get_out->{content}, "$self->{name}: check_post2get: check POSTed '".$self->name."' against fetched");
    }
    $get_out->{content}->{id} = $item_id;

    return ($post_out, $get_out);
}

sub put_and_get{
    my($self, $put_in, $get_in,$params) = @_;
    my($put_out,$put_get_out,$get_out);

    $params //= ();
    
    $put_in->{uri} //= $put_in->{location};

    $get_in->{ignore_fields} //= [];
    $put_in->{ignore_fields} //= [];
    $params->{ignore_fields} //= [];
    my $ignore_fields = [@{$params->{ignore_fields}}, @{$get_in->{ignore_fields}}, @{$put_in->{ignore_fields}}];
    delete $get_in->{ignore_fields};
    delete $put_in->{ignore_fields};

    @{$put_out}{qw/response content request/} = $self->request_put($put_in->{content},$put_in->{uri});
    @{$put_get_out}{qw/response content request/} = $self->check_item_get($put_in->{uri});
    @{$get_out}{qw/response content request/} = $self->check_item_get($get_in->{uri});
    delete $put_get_out->{content_in}->{_links};
    delete $put_get_out->{content_in}->{_embedded};
    foreach my $field (@$ignore_fields){
        delete $put_get_out->{content}->{$field};
        delete $put_in->{content}->{$field};
    }
    if('CODE' eq ref $params->{compare_cb}){
        $params->{compare_cb}->($put_in->{content}, $put_get_out->{content});
    }
    if(!$params->{skip_compare}){
        is_deeply($put_in->{content}, $put_get_out->{content}, "$self->{name}: check put_and_get: check that '$put_in->{uri}' was updated on put;");
    }
    return ($put_out,$put_get_out,$get_out);
}

####--------------------------utils
sub hash2params{
    my($self,$hash) = @_;
    return join '&', map {$_.'='.uri_escape($hash->{$_})} keys %{ $hash };
}

sub resource_fill_file{
    my($self,$filename,$data) = @_;
    $data //= 'aaa';
    write_file($filename,$data);
}

sub resource_clear_file{
    my $cmd = "echo -n '' > $_[1]";
    print "cmd=$cmd;\n";
    `$cmd`;
}

sub get_id_from_hal{
    my($self,$hal,$name) = @_;
    my $embedded = $self->get_embedded_item($hal,$name);
    (my ($id)) = $embedded->{_links}{self}{href}=~ m!${name}/([0-9]*)$! if $embedded;
    return $id;
}

sub get_embedded_item{
    my($self,$hal,$name) = @_;
    $name //= $self->name;
    my $embedded = $hal->{_embedded}->{'ngcp:'.$name} ;
    return 'ARRAY' eq ref $embedded ? $embedded->[0] : $embedded ;
}

sub get_embedded_forcearray{
    my($self,$hal,$name) = @_;
    $name //= $self->name;
    my $embedded = $hal->{_embedded}->{'ngcp:'.$name} ;
    return 'ARRAY' eq ref $embedded ? $embedded : [ $embedded ];
}

sub uri2location{
    my($self,$uri) = @_;
    $uri=~s/^.*?(\/api\/.*$)/$1/;
    return $uri;
}

sub http_code_msg{
    my($self,$code,$message,$res,$content, $check_message) = @_;
    my $message_res;
    my $name = $self->{name} // '';
    $message //= '';
    #print Dumper [caller];
    if ( ($res->code < 300) || ( $code >= 300 ) ) {
        my $res_message = $res->message // '';
        my $content_message = 'HASH' eq ref $content ? $content->{message} // '' : '' ;
        $message_res = $message.' (' . $res->code . ': ' . $res_message . ': ' . $content_message . ')';
        if($check_message){
            my $check_message_content = length($check_message) > 1 ? $check_message : $message;
            ok($content_message =~/$check_message_content/, "$name: check http message: expected: $check_message_content; got: $content_message;");
        }
    } else {
        $content //= $self->get_response_content($res);
        if (defined $content && $content && defined $content->{message}) {
            $message_res = "$name: ".$message . ' (' . $res->message . ': ' . $content->{message} . ')';
        } else {
            $message_res = "$name: ".$message . ' (' . $res->message . ')';
        }
    }
    my $result;
    $code and $result = is($res->code, $code, $message_res);
    if (!$result && $res) {
        push @$failed_http_tests, {response => $res, expected => $code, got => $res->code, message => $message, 'name' => $self->name, 'caller' => [caller(1)]};
    }
    return $result;
}

sub print_statistic {
    my($self) = @_;
    my @long_queries = grep {$_->{time} > 0} @$requests_time;
    print "#---------------------------- REQUESTS LONGER THAN 0 SECOND: ".scalar(@long_queries)."\n";
    print Dumper [map {
            join("\t",$_->{time},$_->{response}->request->method, "\t", $_->{response}->request->uri->as_string)
        } sort {$b->{time} <=> $a->{time}} @long_queries ] if scalar(@long_queries);
    print "#---------------------------- FAILED HTTP CODE CHECKINGS: ".scalar(@$failed_http_tests)."\n";
    print Dumper [map {
            join("\t", $_->{response}->request->method, "\t", $_->{got}, $_->{expected}, $_->{name}, $_->{response}->request->uri->as_string)
        } @$failed_http_tests] if scalar(@$failed_http_tests);
}

sub name_prefix{
    my($self,$name) = @_;
    $name //= $self->name;
    return $name ? $name.': ' : '';
} 

sub get_cached_data{
    my($self) = @_;
    return (-e $self->data_cache_file) ? retrieve($self->data_cache_file) : {};
}

sub replace_cached_data{
    my($self,$data_callback,$restored) = @_;
    $restored //= $self->get_cached_data;
    $data_callback->($restored);
    store $restored,$self->data_cache_file;
    return $restored;
}

sub clear_cache{
    my($self) = @_;
    if(-e $self->data_cache_file){
        my $cmd = "rm ".$self->data_cache_file;
        `$cmd`;
    }
}

sub is_int {
    my $val = shift;
    if($val =~ /^[+-]?[0-9]+$/) {
        return 1;
    }
    return;
}
1;
