package Test::Collection;
#later package should be split into 2: apiclient and testcollection
#testcollection will keep object of the apiclient

#export LOCAL_TEST=https://192.168.x.x:yyyy; perl -I {PATH}/ngcp-panel/t/lib/ {PATH}/ngcp-panel/t/api-xxx.t

use strict;
use Test::More;
use Moose;
use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Net::Domain qw(hostfqdn);
use URI;
use URI::Escape;
use Clone qw/clone/;

use Data::Dumper;


has 'local_test' => (
    is => 'rw',
    isa => 'Str',
    default => $ENV{LOCAL_TEST} // '',
);
has 'catalyst_config' => (
    is => 'rw',
    isa => 'HashRef',
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
    lazy => 1,
    isa => 'LWP::UserAgent',
    builder => 'init_ua',
);
has 'base_uri' => (
    is => 'ro',
    isa => 'Str',
    default => sub {
        $_[0]->{local_test} 
        ? ( length($_[0]->{local_test})>1 ? $_[0]->{local_test} : 'https://127.0.0.1:4443' ) 
        : $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
    },
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
has 'KEEP_CREATED' =>(
    is => 'rw',
    isa => 'Bool',
    default => 1,
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
sub get_catalyst_config{
    my $self = shift;
    my $catalyst_config;
    my $panel_config;
    if ($self->{local_test}) {
        for my $path(qw#../ngcp_panel.conf ngcp_panel.conf#) {
            if(-f $path) {
                $panel_config = $path;
                last;
            }
        }
        $panel_config //= '../ngcp_panel.conf';
        $catalyst_config = Config::General->new($panel_config);   
    } else {
        #taken 1:1 from /lib/NGCP/Panel.pm
        for my $path(qw#/etc/ngcp-panel/ngcp_panel.conf etc/ngcp_panel.conf ngcp_panel.conf#) {
            if(-f $path) {
                $panel_config = $path;
                last;
            }
        }
        $panel_config //= 'ngcp_panel.conf';
        $catalyst_config = Config::General->new($panel_config);   
    }
    my %config = $catalyst_config->getall();
    $self->{catalyst_config} = \%config;
    $self->{panel_config} = $panel_config;
    return $self->{catalyst_config};
}
sub init_ua {
    my $self = shift;
    my $ua = LWP::UserAgent->new;
    my $uri = $self->base_uri;
    $uri =~ s/^https?:\/\///;
    my($user,$pass) = $self->get_role_credentials();
    $ua->credentials( $uri, 'api_admin_http', $user, $pass);
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
    my($user,$pass,$role) = $self->get_role_credentials($role_in);
    $self->runas_role($role);
    $self->ua->credentials( $uri, 'api_admin_http', $user, $pass);
}
sub get_role_credentials{
    my $self = shift;
    my($role) = @_;
    my($user,$pass);
    $role //= $self->runas_role // 'default';
    if($role eq 'default' || $role eq 'admin'){
        $user //= $ENV{API_USER} // 'administrator';
        $pass //= $ENV{API_PASS} // 'administrator';
    }elsif($role eq 'reseller'){
        $user //= $ENV{API_USER_RESELLER} // 'api_test';
        $pass //= $ENV{API_PASS_RESELLER} // 'api_test';
    }
    return($user,$pass,$role);
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
    return $self->base_uri."/api/".$name.($name ? "/" : "").($self->QUERY_PARAMS ? "?".$self->QUERY_PARAMS : "");
}
sub get_uri_get{
    my($self,$query_string, $name) = @_;
    $name //= $self->name;
    return $self->base_uri."/api/".$name.($query_string ? '/?' : '/' ).$query_string;
}
sub get_uri{
    my($self,$add,$name) = @_;
    $add //= '';
    $name //= $self->name;
    return $self->base_uri."/api/".$name.'/'.$add;
}
sub get_uri_firstitem{
    my($self,$name) = @_;
    if(!$self->DATA_CREATED->{FIRST}){
        my($res,$list_collection,$req) = $self->check_item_get($self->get_uri_collection."?page=1&rows=1");
        my $hal_name = $self->get_hal_name($name);
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
    #print $req->as_string;
    my $res = $self->ua->request($req);
    #draft of the debug mode
    #if($res->code >= 400){
    #    print Dumper $req;
    #    print Dumper $res;
    #    print Dumper $res->decoded_content ? JSON::from_json($res->decoded_content) : '';;
    #    die;
    #}
    return $res;
}

sub request_process{
    my($self,$req) = @_;
    #print $req->as_string;
    my $res = $self->ua->request($req);
    my $rescontent = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return ($res,$rescontent,$req);
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
    my $rescontent = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
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
    my $rescontent = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    #print Dumper [$res,$rescontent,$req];
    return wantarray ? ($res,$rescontent,$req) : $res;
}
sub process_data{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $data = $data_in || clone($self->DATA_ITEM);
    defined $data_cb and $data_cb->($data, $data_cb_data);
    return $data;
}
sub request_post{
    my($self, $data_cb, $data_in, $data_cb_data) = @_;
    my $data = $self->process_data($data_cb, $data_in, $data_cb_data);
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
    my $rescontent = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return wantarray ? ($res,$rescontent,$req,$content) : $res;
};

sub request_options{
    my ($self,$uri) = @_;
    # OPTIONS tests
    my $req = HTTP::Request->new('OPTIONS', $self->normalize_uri($uri));
    my $res = $self->request($req);
    my $content = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return($req,$res,$content);
}

sub request_delete{
    my ($self,$uri) = @_;
    # DELETE tests
    #no auto rows for deletion
    my $req = HTTP::Request->new('DELETE', $self->normalize_uri($uri));
    my $res = $self->request($req);
    my $content = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return($req,$res,$content);
}
sub request_get{
    my($self,$uri) = @_;
    my $req = HTTP::Request->new('GET', $self->normalize_uri($uri));
    my $res = $self->request($req);
    my $content = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return wantarray ? ($res, $content, $req) : $res;
}
sub normalize_uri{
    my($self,$uri) = @_;
    $uri ||= $self->get_uri_current;
    if($uri !~/^http/i){
        $uri = $self->base_uri.$uri;
    }
    return $uri;
}
############## end of test machine
############## start of test collection

sub check_options_collection{
    my ($self, $uri) = @_;
    # OPTIONS tests
    $uri //= $self->get_uri_collection;
    my $req = HTTP::Request->new('OPTIONS', $uri );
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
    my $opts = $res->decoded_content ? JSON::from_json($res->decoded_content) : undef;
    $self->http_code_msg(200, "check $area options request", $res,$opts);
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
    my($self, $number, $uniquizer_cb) = @_;
    if(!$self->KEEP_CREATED){
        $self->clear_data_created;
    }
    $self->DATA_CREATED->{ALL} //= {};
    for(my $i = 1; $i <= $number; ++$i) {
        my ($res, $content, $req) = $self->request_post( $uniquizer_cb , undef, { i => $i} );
        $self->http_code_msg(201, "create test item '".$self->name."' $i",$res,$content);
        my $location = $res->header('Location');
        if($location){
            $self->DATA_CREATED->{ALL}->{$location} = { num => $i, content => $content, res => $res, req => $req, location => $location};
            $self->DATA_CREATED->{FIRST} = $location unless $self->DATA_CREATED->{FIRST};
        }
    }
}
sub clear_test_data_all{
    my($self,$uri) = @_;
    my @uris = $uri ? (('ARRAY' eq ref $uri) ? @$uri : ($uri)) : keys %{ $self->DATA_CREATED->{ALL} };
    foreach my $del_uri(@uris){
        my($req,$res,$content) = $self->request_delete($self->base_uri.$del_uri);
        $self->http_code_msg(204, "check delete item $del_uri",$res,$content);
    }
    $self->clear_data_created();
}
sub clear_test_data_dependent{
    my($self,$uri) = @_;
    my($req,$res,$content) = $self->request_delete($self->base_uri.$uri);
    return ('204' eq $res->code);
}
sub check_embedded {
    my($self, $embedded, $check_embedded_cb) = @_;
    defined $check_embedded_cb and $check_embedded_cb->($embedded);
    foreach my $embedded_name(@{$self->embedded_resources}){
        ok(exists $embedded->{_links}->{'ngcp:'.$embedded_name}, "check presence of ngcp:$embedded_name relation");
    }
}

sub check_list_collection{
    my($self, $check_embedded_cb) = @_;
    my $nexturi = $self->get_uri_collection."?page=1&rows=5";
    my @href = ();
    do {
        #print "nexturi=$nexturi;\n";
        my ($res,$list_collection) = $self->check_item_get($nexturi);
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
    is(scalar(keys %{$created_items}), 0, "check if all created test items have been foundin the list");
    if(scalar(keys %{$created_items})){
        print Dumper $created_items;
        print Dumper $listed;
    }
}

sub check_item_get{
    my($self,$uri) = @_;
    $uri ||= $self->get_uri_current;
    my $req = HTTP::Request->new('GET', $uri);
    my $res = $self->request($req);
    #print Dumper $res;
    $self->http_code_msg(200, "fetch uri: $uri", $res);
    my $content = $res->decoded_content ? JSON::from_json($res->decoded_content) : '';
    return wantarray ? ($res, $content, $req) : $res;
}

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

sub check_get2put{
    my($self, $put_data_cb, $uri) = @_;
    #$req->remove_header('Prefer');
    #$req->header('Prefer' => "return=representation");
    # PUT same result again
    my ($res_get, $result_item_get, $req_get) = $self->check_item_get($uri);
    my $item_put_data = clone($result_item_get);
    delete $item_put_data->{_links};
    delete $item_put_data->{_embedded};
    # check if put is ok
    (defined $put_data_cb) and $put_data_cb->($item_put_data);
    my ($res_put,$result_item_put,$req_put) = $self->request_put( $item_put_data, $uri );
    $self->http_code_msg(200, "check_get2put: check put successful",$res_put, $result_item_put);
    is_deeply($result_item_get, $result_item_put, "check_get2put: check put if unmodified put returns the same");
    return ($res_put,$result_item_put,$req_put,$item_put_data);
}

sub check_put2get{
    my($self, $put_data_in, $put_data_cb, $uri) = @_;
    
    my $item_put_data = $self->process_data($put_data_cb, $put_data_in);
    $item_put_data = JSON::to_json($item_put_data);
    my ($res_put,$result_item_put,$req_put) = $self->request_put( $item_put_data, $uri );
    $self->http_code_msg(200, "check_put2get: check put successful",$res_put, $result_item_put);
    
    my ($res_get, $result_item_get, $req_get) = $self->check_item_get($uri);
    delete $result_item_get->{_links};
    delete $result_item_get->{_embedded};
    my $item_id = delete $result_item_get->{id};
    $item_put_data = JSON::from_json($item_put_data);
    is_deeply($item_put_data, $result_item_get, "check_put2get: check PUTed item against POSTed item");
    $result_item_get->{id} = $item_id;
    return ($res_put,$result_item_put,$req_put,$item_put_data,$res_get, $result_item_get, $req_get);
}

sub check_post2get{
    my($self, $post_data_in, $post_data_cb) = @_;
    
    my ($res_post, $result_item_post, $req_post, $item_post_data ) = $self->request_post( $post_data_cb, $post_data_in );
    $self->http_code_msg(201, "check_post2get: POST item '".$self->name."' for check_post2get", $res_post, $result_item_post);
    my $location_post = $self->base_uri.($res_post->header('Location') // '');
    
    my ($res_get, $result_item_get, $req_get) = $self->request_get( $location_post );
    $self->http_code_msg(200, "check_post2get: fetch POSTed test '".$self->name."'", $res_get, $result_item_get);
    delete $result_item_get->{_links};
    my $item_id = delete $result_item_get->{id};
    $item_post_data = JSON::from_json($item_post_data);
    is_deeply($item_post_data, $result_item_get, "check_post2get: check POSTed '".$self->name."' against fetched");
    $result_item_get->{id} = $item_id;
    return ($res_post,$result_item_post,$req_post,$item_post_data, $location_post, $result_item_get);
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
    my ($res,$rescontent,$req) = $self->request_patch( $content );
    $self->http_code_msg(200, "check patched item", $res, $rescontent);
    is($rescontent->{_links}->{self}->{href}, $self->DATA_CREATED->{FIRST}, "check patched self link");
    is($rescontent->{_links}->{collection}->{href}, '/api/'.$self->name.'/', "check patched collection link");
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
    like($content->{message}, qr/is missing a message body/, "check patch missing body response");
}

sub check_patch_body_notarray{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        { foo => 'bar' },
    );
    $self->http_code_msg(400, "check patch no array body", $res, $content);
    like($content->{message}, qr/must be an array/, "check patch missing body response");
}

sub check_patch_op_missed{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ foo => 'bar' }],
    );
    $self->http_code_msg(400, "check patch no op in body", $res, $content);
    like($content->{message}, qr/must have an 'op' field/, "check patch no op in body response");
}

sub check_patch_op_wrong{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'bar' }],
    );
    $self->http_code_msg(400, "check patch invalid op in body", $res, $content);
    like($content->{message}, qr/Invalid PATCH op /, "check patch no op in body response");
}

sub check_patch_opreplace_paramsmiss{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'replace' }],
    );
    $self->http_code_msg(400, "check patch missing fields for op", $res, $content);
    like($content->{message}, qr/Missing PATCH keys /, "check patch missing fields for op response");
}

sub check_patch_opreplace_paramsextra{
    my($self) = @_;
    my ($res,$content,$req) = $self->request_patch(
        [{ op => 'replace', path => '/foo', value => 'bar', invalid => 'sna' }],
    );
    $self->http_code_msg(400, "check patch extra fields for op", $res, $content);
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
    $self->check_options_collection();
    # iterate over collection to check next/prev links and status
    my $listed = $self->check_list_collection();
    $self->check_created_listed($listed);
    # test model item
    if(@$listed){
        $self->check_options_item;
        if(exists $self->methods->{'item'}->{allowed}->{'PUT'}){
            $self->check_put_bundle;
        }
        if(exists $self->methods->{'item'}->{allowed}->{'PATCH'}){
            $self->check_patch_bundle;
        }
    }
}
#utils
sub hash2params{
    my($self,$hash) = @_;
    return join '&', map {$_.'='.uri_escape($hash->{$_})} keys %{ $hash };
}
sub http_code_msg{
    my($self,$code,$message,$res,$content) = @_;
    my $message_res;
    if ( ($res->code < 300) || ( $code >= 300 ) ) {
        $message_res = $message;
    } else {
        $content //= $res->decoded_content ? JSON::from_json($res->decoded_content) : undef;
        if (defined $content && defined $content->{message}) {
            $message_res = $message . ' (' . $res->message . ': ' . $content->{message} . ')';
        } else {
            $message_res = $message . ' (' . $res->message . ')';
        }
    }
    $code and is($res->code, $code, $message_res);
}
1;
