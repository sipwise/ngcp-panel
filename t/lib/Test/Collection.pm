package Test::Collection;
#later package should be split into 2: apiclient and testcollection
#testcollection will keep object of the apiclient

use strict;
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
use Data::Dumper;
use Storable;
use Carp qw(cluck longmess shortmess);

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
    is => 'ro',
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
#has 'subscriber_user' => (
#    is => 'rw',
#    isa => 'Str',
#);
#has 'subscriber_pass' => (
#    is => 'rw',
#    isa => 'Str',
#);
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
    my $ua = LWP::UserAgent->new;
    my $uri = $self->base_uri;
    $uri =~ s/^https?:\/\///;
    my($user,$pass,$role,$realm) = $self->get_role_credentials();
    $ua->credentials( $uri, $realm, $user, $pass);
    $ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
    return $ua;
}
sub runas {
    my $self = shift;
    my($role_in,$uri) = @_;
    $uri //= $self->base_uri;
    $uri =~ s/^https?:\/\///;
    my($user,$pass,$role,$realm) = $self->get_role_credentials($role_in);
    $self->runas_role($role);
    $self->ua->credentials( $uri, $realm, $user, $pass);
}
sub get_role_credentials{
    my $self = shift;
    my($role) = @_;
    my($user,$pass);
    $role //= $self->runas_role // 'default';
    my $realm;
    if($role eq 'default' || $role eq 'admin'){
        $user //= $ENV{API_USER} // 'administrator';
        $pass //= $ENV{API_PASS} // 'administrator';
        $realm = 'api_admin_http';
    }elsif($role eq 'reseller'){
        $user //= $ENV{API_USER_RESELLER} // 'api_test';
        $pass //= $ENV{API_PASS_RESELLER} // 'api_test';
        $realm = 'api_admin_http';
    #}elsif($role eq 'subscriber'){
    ##   I suggest here the same way as for admin and reseller - trough ENV variables
    #    $user //= $self->subscriber_user;
    #    $pass //= $self->subscriber_pass;
    #    $realm = 'subscriber';
    }
    return($user,$pass,$role,$realm);
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
    my $id = $created_info->{location} || '';
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
sub get_uri_collection{
    my($self,$name) = @_;
    $name //= $self->name;
    return $self->normalize_uri("/api/".$name.($name ? "/" : "").($self->QUERY_PARAMS ? "?".$self->QUERY_PARAMS : ""));
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
    my($self,$name,$uri) = @_;
    $name ||= $self->name;
    my $resitem ;
    if(!$uri){
        if(( $name eq $self->name ) && $self->DATA_CREATED->{FIRST}){
            $resitem = $self->get_created_first;
        }
        if(!$resitem && $self->DATA_LOADED->{$name} && @{$self->DATA_LOADED->{$name}}){
            $resitem = $self->DATA_LOADED->{$name}->[0];
        }
    }
    if(!$resitem){
        my ($reshal, $location);
        $uri //= $self->get_uri_collection($name)."?page=1&rows=1";
        #print "uri=$uri;";
        my($res,$list_collection,$req) = $self->check_item_get($self->normalize_uri($uri));
        ($reshal,$location) = $self->get_hal_from_collection($list_collection,$name);
        if($reshal->{total_count} || ('HASH' eq ref $reshal->{content} && $reshal->{content}->{total_count})){
            $self->IS_EMPTY_COLLECTION(0);
            $resitem = { num => 1, content => $reshal, res => $res, req => $req, location => $location };
            $self->DATA_LOADED->{$name} ||= [];
            push @{$self->DATA_LOADED->{$name}}, $resitem;
        }else{
            $self->IS_EMPTY_COLLECTION(1);
        }
    }
    return $resitem;
}
sub get_hal_from_collection{
    my($self,$list_collection,$name) = @_;
    $name ||= $self->name;
    my $hal_name = $self->get_hal_name($name);
    my($reshal,$location);
    if(ref $list_collection->{_links}->{$hal_name} eq "HASH") {
#found first subscriber
        $reshal = $list_collection;
        $location = $reshal->{_links}->{$hal_name}->{href};
    } elsif( $list_collection->{_embedded} && ref $list_collection->{_embedded}->{$hal_name} eq 'ARRAY') {
        $reshal = $list_collection->{_embedded}->{$hal_name}->[0];
        $location = $reshal->{_links}->{self}->{href};
    }elsif( ref $list_collection eq 'HASH' && $list_collection->{_links}->{self}->{href}) {
#preferencedefs collection
        $reshal = $list_collection;
        $location = $reshal->{_links}->{self}->{href};
    }
    return ($reshal,$location);
}
sub get_created_first{
    my($self) = @_;
    return $self->DATA_CREATED->{FIRST} ? $self->DATA_CREATED->{ALL}->{$self->DATA_CREATED->{FIRST}} : undef;
}
sub get_uri_current{
    my($self) = @_;
    $self->URI_CUSTOM and return $self->URI_CUSTOM;
    return $self->get_uri_item;
}

sub encode_content{
    my($self,$content, $type) = @_;
    $type //= $self->ENCODE_CONTENT;
    my %json_types = (
        'application/json' => 1,
        'application/json-patch+json' => 1,
        'json' => 1,
    );
    #print "1. content=$content;\n\n";
    if($content){
        if( $json_types{$type} && (('HASH' eq ref $content) ||('ARRAY' eq ref $content))  ){
            return JSON::to_json($content);
        }
    }
    #print "2. content=$content;\n\n";
    return $content;
}
sub request{
    my($self,$req) = @_;


    my $credentials = {};
    (@$credentials{qw/user password/},undef,undef) = $self->get_role_credentials();
    my $curl = Test::HTTPRequestAsCurl::as_curl($req, credentials => $credentials );
    if($self->DEBUG){
        print $req->as_string;
        print "$curl\n\n";
    }
    my $res = $self->ua->request($req);
    #draft of the debug mode
    if($self->DEBUG){
        if($res->code >= 400){
            print Dumper $req;
            print Dumper $res;
            print Dumper $self->get_response_content($res);
            #die;
        }
    }
    return $res;
}

sub request_process{
    my($self,$req) = @_;
    #print $req->as_string;
    my $res = $self->ua->request($req);
    my $rescontent = $self->get_response_content($res);
    return ($res,$rescontent,$req);
}
sub get_request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    $uri = $self->normalize_uri($uri);
    #This is for multipart/form-data cases
    $content = $self->encode_content($content, $self->content_type->{PUT});
    my $req = POST $uri,
        Content_Type => $self->content_type->{PUT},
        $content ? ( Content => $content ) : ();
    $req->method('PUT');
    $req->header('Prefer' => 'return=representation');
    return $req;
}
sub get_request_patch{
    my($self,$uri) = @_;
    $uri ||= $self->get_uri_current;
    $uri = $self->normalize_uri($uri);
    my $req = HTTP::Request->new('PATCH', $uri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => $self->content_type->{PATCH} );
    return $req;
}
sub request_put{
    my($self,$content,$uri) = @_;
    $uri ||= $self->get_uri_current;
    my $req = $self->get_request_put( $content, $self->normalize_uri($uri) );
    my $res = $self->request($req);
    my $rescontent = $self->get_response_content($res);
    return wantarray ? ($res,$rescontent,$req) : $res;
}
sub request_patch{
    my($self,$content, $uri, $req) = @_;
    $uri ||= $self->get_uri_current;
    $req ||= $self->get_request_patch($uri);
    #patch is always a json
    $content = $self->encode_content($content, $self->content_type->{PATCH});
    $content and $req->content($content);
    my $res = $self->request($req);
    my $rescontent = $self->get_response_content($res);
    #print Dumper [$res,$rescontent,$req];
    return wantarray ? ($res,$rescontent,$req) : $res;
}

sub request_post{
    my($self, $content, $uri, $req) = @_;
    $uri ||= $self->get_uri_collection;
    $uri = $self->normalize_uri($uri);
    $content = $self->encode_content($content, $self->content_type->{POST} );
    #form-data is set automatically, despite on $self->content_type->{POST}
    $req ||= POST $uri,
        Content_Type => $self->content_type->{POST},
        Content => $content;
    $req->header('Prefer' => 'return=representation');
    my $res = $self->request($req);
    my $rescontent = $self->get_response_content($res);
    return wantarray ? ($res,$rescontent,$req,$content) : $res;
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
    my $req = HTTP::Request->new('DELETE', $self->normalize_uri($uri));
    my $res = $self->request($req);
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
    my($self,$uri) = @_;
    my $req = HTTP::Request->new('GET', $self->normalize_uri($uri));
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
            ok(grep(/^$opt$/, @hopts), "$self->{name}: check for existence of '$opt' in Allow header");
            ok(grep(/^$opt$/, @{ $opts->{methods} }), "$self->{name}: check for existence of '$opt' in body");
        }else{
            ok(!grep(/^$opt$/, @hopts), "$self->{name}: check for absence of '$opt' in Allow header");
            ok(!grep(/^$opt$/, @{ $opts->{methods} }), "$self->{name}: check for absence of '$opt' in body");
        }
    }
}

sub check_list_collection{
    my($self, $check_embedded_cb) = @_;
    my $nexturi = $self->get_uri_collection."?page=1&rows=5";
    my @href = ();
    do {
        #print "nexturi=$nexturi;\n";
        my ($res,$list_collection) = $self->check_item_get($nexturi);
        my $selfuri = $self->normalize_uri($list_collection->{_links}->{self}->{href});
        is($selfuri, $nexturi, "$self->{name}: check _links.self.href of collection");
        my $colluri = URI->new($selfuri);
        if(($list_collection->{total_count} && $list_collection->{total_count} > 0 ) || !$self->ALLOW_EMPTY_COLLECTION){
            ok($list_collection->{total_count} > 0, "$self->{name}: check 'total_count' of collection");
        }

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, "$self->{name}: check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        ok($rows != 0, "check existance of the 'rows'");
        if($page == 1) {
            ok(!exists $list_collection->{_links}->{prev}->{href}, "$self->{name}: check absence of 'prev' on first page");
        } else {
            ok(exists $list_collection->{_links}->{prev}->{href}, "$self->{name}: check existence of 'prev'");
        }
        if(($rows != 0) && ($list_collection->{total_count} / $rows) <= $page) {
            ok(!exists $list_collection->{_links}->{next}->{href}, "$self->{name}: check absence of 'next' on last page");
        } else {
            ok(exists $list_collection->{_links}->{next}->{href}, "$self->{name}: check existence of 'next'");
        }

        if($list_collection->{_links}->{next}->{href}) {
            $nexturi = $self->normalize_uri($list_collection->{_links}->{next}->{href});
        } else {
            $nexturi = undef;
        }

        my $hal_name = $self->get_hal_name;
        if(($list_collection->{total_count} && $list_collection->{total_count} > 0 ) || !$self->ALLOW_EMPTY_COLLECTION){
            ok(((ref $list_collection->{_links}->{$hal_name} eq "ARRAY" ) ||
                (ref $list_collection->{_links}->{$hal_name} eq "HASH" ) ), "$self->{name}: check if 'ngcp:".$self->name."' is array/hash-ref");
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
    is(scalar(keys %{$created_items}), 0, "$self->{name}: check if all created test items have been foundin the list");
    if(scalar(keys %{$created_items})){
        print Dumper $created_items;
        print Dumper $listed;
    }
}

sub check_embedded {
    my($self, $embedded, $check_embedded_cb) = @_;
    defined $check_embedded_cb and $check_embedded_cb->($embedded);
    foreach my $embedded_name(@{$self->embedded_resources}){
        ok(exists $embedded->{_links}->{'ngcp:'.$embedded_name}, "$self->{name}: check presence of ngcp:$embedded_name relation");
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
    $self->http_code_msg(400, "check put invalid prefer", $res, $content);
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
    $self->check_put_prefer_wrong;
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
    my($self, $uri, $msg) = @_;
    $msg //= '';
    $uri ||= $self->get_uri_current;
    $uri = $self->normalize_uri($uri);
    my ($res, $content, $req) = $self->request_get($uri);
    $self->http_code_msg(200, $msg.($msg?": ":"")."fetch uri: $uri", $res);
    return wantarray ? ($res, $content, $req) : $res;
}
sub process_data{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $data = $data_in || clone($self->DATA_ITEM);
    defined $data_cb and $data_cb->($data, $data_cb_data);
    return $data;
}
sub get_item_post_content{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $data = $self->process_data($data_cb, $data_in, $data_cb_data);
    #print Dumper $data;
    my $content = {
        $data->{json} ? ( json => JSON::to_json(delete $data->{json}) ) : (),
        %$data,
    };
    return $content;
}
sub check_item_post{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $content = $self->get_item_post_content($data_cb, $data_in, $data_cb_data);
    #print Dumper $content;
    my ($res,$rescontent,$req) = $self->request_post($content);#,$uri,$req
    return wantarray ? ($res,$rescontent,$req,$content) : $res;
};
sub check_create_correct{
    my($self, $number, $uniquizer_cb) = @_;
    if(!$self->KEEP_CREATED){
        $self->clear_data_created;
    }
    $self->DATA_CREATED->{ALL} //= {};
    my @created = ();
    for(my $i = 1; $i <= $number; ++$i) {
        my $created_info={};
        my ($res, $content, $req, $content_post) = $self->check_item_post( $uniquizer_cb , undef, { i => $i } );
        $self->http_code_msg(201, "create test item '".$self->name."' $i",$res,$content);
        my $location = $res->header('Location');
        if($location){
            #some interfaces (e.g. subscribers) don't provide hal after creation - is it correct, by the way?
            my $get ={};
            if(!$content){
                @$get{qw/res_get content_get req_get/} = $self->check_item_get($location,"no object returned after POST");
            }
            $created_info = {
                num => $i,
                content => $content ? $content : $get->{content_get},
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
    my($self,$uri) = @_;
    my @uris = $uri ? (('ARRAY' eq ref $uri) ? @$uri : ($uri)) : keys %{ $self->DATA_CREATED->{ALL} };
    foreach my $del_uri(@uris){
        $del_uri = $self->normalize_uri($del_uri);
        my($req,$res,$content) = $self->request_delete($del_uri);
        $self->http_code_msg(204, "check delete item $del_uri",$res,$content);
    }
    $self->clear_data_created();
    return \@uris;
}
sub clear_test_data_dependent{
    my($self,$uri) = @_;
    my($req,$res,$content) = $self->request_delete($self->normalize_uri($uri));
    return ('204' eq $res->code);
}

sub check_get2put{
    my($self, $put_in, $get_in) = @_;

    my($put_out,$get_out);

    $get_in //= {};
    $put_in //= {};
    $get_in->{uri} //= $put_in->{uri};
    $put_in->{uri} //= $get_in->{uri};

    @$get_out{qw/response content request/} = $self->check_item_get($get_in->{uri});
    $put_out->{content_in} = clone($get_out->{content});
    delete $put_out->{content_in}->{_links};
    delete $put_out->{content_in}->{_embedded};
    # check if put is ok
    (defined $put_in->{data_cb}) and $put_in->{data_cb}->($put_out->{content_in});
    @{$put_out}{qw/response content request/} = $self->request_put( $put_out->{content_in}, $put_in->{uri} );
    $self->http_code_msg(200, "check_get2put: check put successful", $put_out->{response},  $put_out->{content} );
    is_deeply($get_out->{content}, $put_out->{content}, "$self->{name}: check_get2put: check put if unmodified put returns the same");
    return ($put_out,$get_out);
}

sub check_put2get{
    my($self, $put_in, $get_in, $check_cb_or_switch) = @_;

    my($put_out,$get_out);

    $get_in //= {};
    $put_in->{uri} //= $put_in->{location};
    $get_in->{uri} //= $put_in->{uri};
    $put_in->{uri} //= $get_in->{uri};
    $get_out->{uri} = $get_in->{uri};
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
    if('CODE' eq ref $check_cb_or_switch){
        $check_cb_or_switch->($put_out,$get_out);
    }
    if(!$check_cb_or_switch || 'CODE' eq ref $check_cb_or_switch){
        is_deeply($get_out->{content}, $put_out->{content_in}, "$self->{name}: check_put2get: check PUTed item against GETed item");
    }
    $get_out->{content}->{id} = $item_id;
    $put_out->{content_in}->{id} = $item_id_in;
    return ($put_out,$get_out);
}

sub check_post2get{
    my($self, $post_in, $get_in) = @_;
    $get_in //= {};
    #$post = {data_in=>,data_cb=>};
    #$get = {uri=>}
    #return
    #$post={response,content,request,data,location}
    #$get=={response,content,request,uri}
    my($post_out,$get_out);
    @{$post_out}{qw/response content request data/} = $self->check_item_post( $post_in->{data_cb}, $post_in->{data_in} );
    $self->http_code_msg(201, "check_post2get: POST item '".$self->name."' for check_post2get", @{$post_out}{qw/response content/});
    $post_out->{location} = $self->normalize_uri(($post_out->{response}->header('Location') // ''));

    $get_out->{uri} = $get_in->{uri} // $post_out->{location};
    @{$get_out}{qw/response content request/} = $self->check_item_get( $get_out->{uri}, "check_post2get: fetch POSTed test '".$self->name."'" );

    delete $get_out->{content}->{_links};
    my $item_id = delete $get_out->{content}->{id};
    is_deeply($post_out->{data}, $get_out->{content}, "$self->{name}: check_post2get: check POSTed '".$self->name."' against fetched");
    $get_out->{content}->{id} = $item_id;

    return ($post_out, $get_out);
}
sub put_and_get{
    my($self, $put_in, $get_in) = @_;
    my($put_out,$put_get_out,$get_out);
    @{$put_out}{qw/response content request/} = $self->request_put($put_in->{content},$put_in->{uri});
    @{$put_get_out}{qw/response content request/} = $self->check_item_get($put_in->{uri});
    @{$get_out}{qw/response content request/} = $self->check_item_get($get_in->{uri});
    delete $put_get_out->{content_in}->{_links};
    delete $put_get_out->{content_in}->{_embedded};
    is_deeply($put_in->{content}, $put_get_out->{content}, "$self->{name}: check that '$put_in->{uri}' was updated on put;");
    return ($put_out,$put_get_out,$get_out);
}

####--------------------------utils
sub hash2params{
    my($self,$hash) = @_;
    return join '&', map {$_.'='.uri_escape($hash->{$_})} keys %{ $hash };
}
sub resource_fill_file{
    #$_[0]->{faxfile}->[0]
    my $cmd = "echo 'aaa' > $_[1]";
    print "cmd=$cmd;\n";
    `$cmd`;
}
sub resource_clear_file{
    my $cmd = "echo -n '' > $_[1]";
    print "cmd=$cmd;\n";
    `$cmd`;
}
sub get_id_from_hal{
    my($self,$hal,$name) = @_;
    $name //= $self->name;
    my $id = $hal->{_embedded}->{'ngcp:'.$name}->{_links}{self}{href} =~ m!${name}/([0-9]*)$!;
    return $id;
}
sub uri2location{
    my($self,$uri) = @_;
    $uri=~s/^.*?(\/api\/.*$)/$1/;
    return $uri;
}
sub http_code_msg{
    my($self,$code,$message,$res,$content) = @_;
    my $message_res;
    my $name = $self->{name} // '';
    $message //= '';
    if ( ($res->code < 300) || ( $code >= 300 ) ) {
        my $res_message = $res->message // '';
        my $content_message = 'HASH' eq ref $content ? $content->{message} // '' : '' ;
        $message_res = $message.' (' . $res_message . ': ' . $content_message . ')';
    } else {
        $content //= $self->get_response_content($res);
        if (defined $content && $content && defined $content->{message}) {
            $message_res = "$name: ".$message . ' (' . $res->message . ': ' . $content->{message} . ')';
        } else {
            $message_res = "$name: ".$message . ' (' . $res->message . ')';
        }
    }
    $code and is($res->code, $code, $message_res);
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

1;
