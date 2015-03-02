use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON qw();
use Test::More;
use Data::Dumper;
use File::Basename;
use Clone qw/clone/;

#my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my $uri = 'https://192.168.56.7:1444';

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{ API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;
$ua->credentials( 'https://192.168.56.7:1444/', '', 'administrator', 'administrator' );
#$ua->ssl_opts(
#    SSL_cert_file   => $valid_ssl_client_cert,
#    SSL_key_file    => $valid_ssl_client_key,
#    SSL_ca_file     => $ssl_ca_cert,
#);
$ua->ssl_opts(
    verify_hostname => 0,
    SSL_verify_mode => 0x00,
);

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/pbxdevicemodels/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodels", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

my $MODEL = {
    json => {
        "model"=>"ATA22",
        #3.7relative tests
        "type"=>"phone",
        "bootstrap_method"=>"http",
        #"bootstrap_config_http_sync_uri"=>"http=>//[% client.ip %]/admin/resync",
        #"bootstrap_config_http_sync_params"=>"[% server.uri %]/$MA",
        #"bootstrap_config_http_sync_method"=>"GET",
        #/3.7relative tests
        "reseller_id"=>"1",
        "vendor"=>"Cisco",
        "linerange"=>[
            {
                "keys"=>[
                    {"y"=>"390","labelpos"=>"left","x"=>"510"},
                    {"y"=>"350","labelpos"=>"left","x"=>"510"}
                ],
                "can_private"=>"1",
                "can_shared"=>"0",
                "can_blf"=>"0",
                "name"=>"Phone Ports",
#test duplicate creation #"id"=>1311,
            }
        ]
    },
    #'front_image' => [ dirname($0).'/resources/api_devicemodels_front_image.jpg' ],
    'front_image' => [ dirname($0).'/resources/empty.txt' ],
};
my $request_sub={
    pbxdevicemodels => sub {
        my($model_cb,$model_in) = @_;
        my $model = $model_in || clone($MODEL);
        $model_cb and $model_cb->($model);
        my $content = {
            json => JSON::to_json($model->{json}),
            'front_image' => $model->{front_image},
        };
        my $req = POST $uri.'/api/pbxdevicemodels/', Content_Type => 'form-data', Content => $content;
        my $res = $ua->request($req);
        return $res;
    } 
};
# collection test
my $firstmodel = undef;
my @allmodels = ();
{
    # create 6 new billing models
    my %models = ();
    for(my $i = 1; $i <= 6; ++$i) {
        my $res = $request_sub->{pbxdevicemodels}->( sub{ $_[0]->{json}->{model} .= "_$i"; } );
        is($res->code, 201, "create test billing model $i");
        $models{$res->header('Location')} = 1;
        push @allmodels, $res->header('Location');
        $firstmodel = $res->header('Location') unless $firstmodel;
    }

    # try to create model without reseller_id
    {
        my $res = $request_sub->{pbxdevicemodels}->(sub{delete $_[0]->{json}->{reseller_id};});
        print Dumper $res;
        is($res->code, 422, "create model without reseller_id");
        my $err = JSON::from_json($res->decoded_content);
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
    }
    # try to create model with empty reseller_id
    {
        my $res = $request_sub->{pbxdevicemodels}->(sub{$_[0]->{json}->{reseller_id} = undef;});
        is($res->code, 422, "create model with empty reseller_id");
        my $err = JSON::from_json($res->decoded_content);
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
    }

    # try to create model with invalid reseller_id
    {
        my $res = $request_sub->{pbxdevicemodels}->(sub{$_[0]->{json}->{reseller_id} = 99999;});
        is($res->code, 422, "create model with invalid reseller_id");
        my $err = JSON::from_json($res->decoded_content);
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /Invalid 'reseller_id'/, "check error message in body");
    } 

    # iterate over collection to check next/prev links and status

    is(scalar(keys %models), 0, "check if all test models have been found");
}

# test model item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstmodel);
    $res = $ua->request($req);
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

    $req = HTTP::Request->new('GET', $uri.'/'.$firstmodel);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one contract item");
    my $model = JSON::from_json($res->decoded_content);
    ok(exists $model->{reseller_id} && $model->{reseller_id}->is_int, "check existence of reseller_id");
    ok(exists $model->{handle}, "check existence of handle");
    ok(exists $model->{name}, "check existence of name");
    
    # PUT same result again
    my $old_model = { %$model };
    delete $model->{_links};
    delete $model->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstmodel);
    
    # check if it fails without content type
    $req->remove_header('Content-Type');
    $req->header('Prefer' => "return=minimal");
    $res = $ua->request($req);
    is($res->code, 415, "check put missing content type");

    # check if it fails with unsupported content type
    $req->header('Content-Type' => 'application/xxx');
    $res = $ua->request($req);
    is($res->code, 415, "check put invalid content type");

    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/json');

    # check if it fails with invalid Prefer
    $req->header('Prefer' => "return=invalid");
    $res = $ua->request($req);
    is($res->code, 400, "check put invalid prefer");


    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=representation");

    # check if it fails with missing body
    $res = $ua->request($req);
    is($res->code, 400, "check put no body");

    # check if put is ok
    $req->content(JSON::to_json($model));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_model = JSON::from_json($res->decoded_content);
    is_deeply($old_model, $new_model, "check put if unmodified put returns the same");

    # check if we have the proper links
    # TODO: fees, reseller links
    #ok(exists $new_contract->{_links}->{'ngcp:resellers'}, "check put presence of ngcp:resellers relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstmodel);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    my $t = time;
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => 'patched name '.$t } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched model item");
    my $mod_model = JSON::from_json($res->decoded_content);
    is($mod_model->{name}, "patched name $t", "check patched replace op");
    is($mod_model->{_links}->{self}->{href}, $firstmodel, "check patched self link");
    is($mod_model->{_links}->{collection}->{href}, '/api/pbxdevicemodels/', "check patched collection link");
    

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef reseller");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid reseller");

    # TODO: invalid handle etc
}

done_testing;

# vim: set tabstop=4 expandtab:
