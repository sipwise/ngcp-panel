package Test::FakeData;

use strict;
use warnings;

use Moose::Exporter;
use Moose;
use Test::Collection;
use JSON;
use Test::More;
use File::Basename;
use Data::Dumper;
use Test::DeepHashUtils qw(reach nest deepvalue);
use Clone qw/clone/;
use File::Slurp qw/read_file/;
use URI::Escape;
use Storable;
use File::Grep qw/fgrep/;
use feature 'state';
use Storable;
use File::Temp qw(tempfile);


Moose::Exporter->setup_import_methods(
    as_is     => [ 'seq' ],
);

sub BUILD {
    my $self = shift;
    if($self->test_machine->cache_data){
        $self->read_cached_data();
    }
}
has 'data_cache_file' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub {
        return shift->test_machine->data_cache_file;
    },
);
has 'test_machine' =>(
    is => 'rw',
    isa => 'Test::Collection',
    default => sub { Test::Collection->new ( 'KEEP_CREATED' => 0 ) },
);
has 'created' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);
has 'loaded' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);
has 'searched' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);
has 'undeletable' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
);
has 'data_default' => (
    is => 'rw',
    isa => 'HashRef',
    builder => 'build_data_default',
);
has 'data' => (
    is => 'rw',
    isa => 'HashRef',
    builder => 'build_data',
);
has 'use_data_callbacks' => (
    is => 'rw',
    isa => 'Bool',
    default => sub { 0 },
);
has 'keep_db_data' => (
    is => 'rw',
    isa => 'Bool',
    default => sub { 0 },
);
has 'FLAVOUR' => (
    is => 'rw',
    isa => 'Str',
);

sub build_data_default{
    return {
        'products' => [
            {
                id                 => 1,
                reseller_id        => undef,
                class              => 'pstnpeering',
                handle             => 'PSTN_PEERING',
                name               => 'PSTN Peering',
                on_sale            => 1,
                price              => undef,
                weight             => undef,
                billing_profile_id => undef,
            },{
                id                 => 2,
                reseller_id        => undef,
                class              => 'sippeering',
                handle             => 'SIP_PEERING',
                name               => 'PSTN Peering',
                on_sale            => 1,
                price              => undef,
                weight             => undef,
                billing_profile_id => undef,
            },{
                id                 => 3,
                reseller_id        => undef,
                class              => 'reseller',
                handle             => 'VOIP_RESELLER',
                name               => 'VoIP Reseller',
                on_sale            => 1,
                price              => undef,
                weight             => undef,
                billing_profile_id => undef,
            },
        ],
        'contracts' => {
            id                  => 1,
            customer_id         => undef,
            reseller_id         => undef,
            contact_id          => undef,
            order_id            => undef,
            status              => 'active',
            modify_timestamp    => '0',
            create_timestamp    => '0',
            activate_timestamp  => '0',
            terminate_timestamp => undef,
        },
        'resellers' => {
            id          => 1,
            contract_id => 1,
            name        => 'default',
            status      => 'active',
        },
        'billing_mappings' => {
            id                 => 1,
            start_date         => undef,
            end_date           => undef,
            billing_profile_id => undef,
            contract_id        => 1,
            product_id         => 3,
        },
        'billing_profiles' => {
            id                 => 1,
            reseller_id        => 1,
            handle             => 'default',
            name               => 'Default Billing Profile',
            prepaid            => 1,
            interval_charge    => 0,
            interval_free_time => 0,
            interval_free_cash => 0,
            interval_unit      => 'month',
            interval_count     => 1,
            currency           => undef,
            vat_rate           => 0,
            vat_included       => 0,
        },
        'billing_zones' => {
            id                 => 1,
            billing_profile_id => 1,
            zone               => 'Free Default Zone',
            detail             => 'All Destinations',
        },
        'billing_fees' => {
            id                      => 1,
            billing_profile_id      => 1,
            billing_zone_id         => 1,
            destination             => '.*',
            type                    => 'call',
            onpeak_init_rate        => 0,
            onpeak_init_interval    => 600,
            onpeak_follow_rate      => 0,
            onpeak_follow_interval  => 600,
            offpeak_init_rate       => 0,
            offpeak_init_interval   => 600,
            offpeak_follow_rate     => 0,
            offpeak_follow_interval => 600,
        },
        'domains' => {
            domain => 'voip.sipwise.local',
            local  => 1,
        }
    };
}

sub build_data{
    my ($self) = @_;
    my $data = {
        'applyrewrites' => {
            'data' => {
                direction => "caller_in",
                number => "test",
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
            },
        },
        'billingnetworks' => {
            'data' => {
                name        => "api_test billingnetworks",
                description => "api_test billingnetworks",
                blocks     => [
                    {ip=>'10.0.5.9',mask=>24},
                    {ip=>'10.0.6.9',mask=>24},
                ],
            },
        },
       'callcontrols' => {
            'data' => {
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
                destination   => "api_test",
            },
        },
        'cfsourcesets' => {
            'data' => {
                sources => [{source => "test",}],
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
                name => "from_test",
                mode => "whitelist",
            },
            'query' => ['name','subscriber_id'],
            'data_callbacks' => {
                'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
            },
        },
        'customerlocations' => {
            'data' => {
                blocks     => [
                    {ip=>'10.0.5.9',mask=>24},
                    {ip=>'10.0.6.9',mask=>24},
                ],
                contract_id => sub { return shift->get_id('contracts',@_); },
                name => "test_api",
                description => "test_api",
            },
            'query' => ['name'],
            'data_callbacks' => {
                'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
            },
        },
        'ncoslnpcarriers' => {
            'data' => {
                ncos_level_id  => sub { return shift->get_id('ncoslevels',@_); },
                description => "test_api",
                carrier_id => sub { return shift->get_id('lnpcarriers',@_); },
            },
        },
        'ncospatterns' => {
            'data' => {
                ncos_level_id  => sub { return shift->get_id('ncoslevels',@_); },
                description => "test_api",
                pattern => "aaabbbccc",
            },
        },
        'partycallcontrols' => {
            'data' => {
                callee => "test",
                caller => "test",
                callid => "test",
                status => "test",
                token  => "test",
                type   => "pcc",#'pcc' or 'sms'
            },
        },
        'profilepackages' => {
            'data' => {
                name        => "test",
                description => "test",
                initial_profiles  => [
                    {
                        profile_id => sub { return shift->get_id('billingprofiles',@_); },
                        #network_id => sub { return shift->get_id('billingnetworks',@_); },
                    }
                ],
            },
        },
        'rtcsessions' => {
            'data' => {
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
            },
        },
        'topupcash' => {
            'data' => {
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
                amount => 1.0,
            },
        },
        'topupvouchers' => {
            'data' => {
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
                code => 'test',
            },
        },
        'upnrewritesets' => {
            'data' => {
                new_cli => "test",
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
                upn_rewrite_sources => [{ pattern => 'aaa'},{ pattern => 'bbb'}],
            },
        },
        'systemcontacts' => {
            'data' => {
                email     => 'api_test_reseller@reseller.invalid',
                firstname => 'api_test first',
                lastname  => 'api_test last',
            },
            'query' => ['email'],
            'delete_potentially_dependent' => 1,
        },
        'customercontacts' => {
            'data' => {
                firstname   => 'api_test cust_contact_first',
                lastname    => 'api_test cust_contact_last',
                email       => 'api_test_cust_contact@custcontact.invalid',
                reseller_id => sub { return shift->get_id('resellers',@_); },
            },
            'query' => ['email'],
            'delete_potentially_dependent' => 1,
        },
        'contracts'   => {
            'data' => {
                contact_id         => sub { return shift->get_id('systemcontacts',@_); },
                status             => 'active',
                external_id        => 'api_test',
                #type               => sub { return value_request('contracts','type',['reseller']); },
                type               => 'reseller',
                billing_profile_id => sub { return shift->get_id('billingprofiles',@_); },
            },
            'default' => 'contracts',
            'query' => ['external_id'],
            'no_delete_available' => 1,
        },
        'resellers' => {
            'data' => {
                contract_id => sub { return shift->get_id('contracts', @_ ); },
                name        => 'api_test test reseller',
                status      => 'active',
            },
            'default' => 'resellers',
            'query' => ['name'],
            'no_delete_available' => 1,
        },
        'customers' => {
            'data' => {
                status             => 'active',
                contact_id         => sub { return shift->get_id('customercontacts',@_); },
                billing_profile_id => sub { return shift->get_id('billingprofiles',@_); },
                max_subscribers    => undef,
                external_id        => 'api_test customer',
                type               => 'pbxaccount',#sipaccount
            },
            'query' => ['external_id'],
            'no_delete_available' => 1,
            #'flavour' => {
            #    'another_one' => {
            #        'data' => {
            #            'external_id' => 'pbx_account_2',
            #            'type'        => 'pbxaccount',
            #        }
            #    }
            #},
        },
        'customer_sipaccount' => {
            'data' => {
                status             => 'active',
                contact_id         => sub { return shift->create_get_id('customercontacts',@_);},
                billing_profile_id => sub { return shift->create_get_id('billingprofiles',@_); },
                external_id        => 'api_test customer sipaccount',
                type               => 'sipaccount',
            },
            'query' => ['external_id'],
            'no_delete_available' => 1,
            'collection' => 'customers',
        },
        'soundhandles_custom_announcements' => {
            'data' => {
                group              => 'custom_announcements',
            },
            'query' => ['group'],
            'no_delete_available' => 1,
            'collection' => 'soundhandles',
        },
        'billingprofiles' => {
            'data' => {
                name        => 'api_test'.time(),
                handle      => 'api_test'.time(),
                reseller_id => sub { return shift->get_id('resellers',@_); },
            },
            'default' => 'billing_profiles',
            'no_delete_available' => 1,
            'dependency_requires_recreation' => ['resellers'],
            'data_callbacks' => {
                'uniquizer_cb' => sub { 
                    Test::FakeData::string_uniquizer(\$_[0]->{name});
                    Test::FakeData::string_uniquizer(\$_[0]->{handle});
                },
            },
        },
        'subscriberprofilesets' => {
            'data' => {
                name        => 'api_test_subscriberprofileset',
                reseller_id => sub { return shift->get_id('resellers',@_); },
                description => 'api_test_subscriberprofileset',
            },
            'query' => ['name'],
            'data_callbacks' => {
                'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
            },
        },
        'subscriberprofiles' => {
            'data' => {
                name           => 'api_test subscriberprofile',
                profile_set_id => sub { return shift->get_id('subscriberprofilesets',@_); },
                description    => 'api_test subscriberprofile',
            },
            'query' => ['name'],
            'data_callbacks' => {
                'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
            },
        },
        'pbxdeviceconfigs' => {
            'data' => {
                device_id    => sub { return shift->get_id('pbxdevicemodels',@_); },
                version      => 'api_test 1.1',
                content_type => 'text/plain',
            },
            'query' => ['version'],
            'create_special'=> sub {
                my ($self,$collection_name,$test_machine) = @_;
                my $prev_params = $test_machine->get_cloned('content_type','QUERY_PARAMS');
                $test_machine->content_type->{POST} = $self->data->{$collection_name}->{data}->{content_type};
                $test_machine->QUERY_PARAMS($test_machine->hash2params($self->data->{$collection_name}->{data}));
                my $created = $test_machine->check_create_correct(1, sub {return 'test_api_empty_config';} );
                $test_machine->set(%$prev_params);
                return $created;
            },
            'no_delete_available' => 1,
        },
        'pbxdeviceprofiles' => {
            'data' => {
                config_id    => sub { return shift->get_id('pbxdeviceconfigs',@_); },
                name         => 'api_test profile 1.1',
            },
            'query' => ['name'],
            'no_delete_available' => 1,
            'data_callbacks' => {
                'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
            },
        },
        'rewriterulesets' => {
            'data' => {
                reseller_id     => sub { return shift->get_id('resellers',@_); },
                name            => 'api_test',
                description     => 'api_test rule set description',
                caller_in_dpid  => '1',
                callee_in_dpid  => '2',
                caller_out_dpid => '3',
                callee_out_dpid => '4',
            },
            'query' => ['name'],
            'data_callbacks' => {
                'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
            },
        },
    };
    $self->process_data($data);
    return $data;
}

sub process_data{
    my($self,$data,$collections_slice) = @_;
    $collections_slice //= [keys %$data];
    foreach my $collection_name( @$collections_slice ){
        if($self->FLAVOUR && exists $data->{$collection_name}->{flavour} && exists $data->{$collection_name}->{flavour}->{$self->FLAVOUR}){
            $data = {%$data, %{$data->{$collection_name}->{flavour}->{$self->FLAVOUR}}};
        }
    }
    #$self->clear_db($data);
    #incorrect place, leave it for the next timeframe to work on it
    #$self->load_db($data);
}

sub apply_data {
    my($self, $alternative_data) = @_;
    foreach my $collection (keys %$alternative_data) {
        my @keys = keys %{$alternative_data->{$collection}};
        @{$self->{data}->{$collection}->{data}}{@keys} = @{$alternative_data->{$collection}}{@keys};
    }
}

sub load_db{
    my($self,$data,$collections_slice) = @_;
    $data //= $self->data;
    $collections_slice //= [keys %$data];
    foreach my $collection_name( @$collections_slice ){
        if((!exists $self->loaded->{$collection_name}) && $data->{$collection_name}->{query}){
            my(undef,$content) = $self->search_item($collection_name,$data);
            if($content->{total_count}){
                my $values = $content->{_embedded}->{$self->test_machine->get_hal_name($self->get_collection_interface($collection_name))};
                $values = ('HASH' eq ref $values) ? [$values] : $values;
                $self->loaded->{$collection_name} = [ map {
                    {
                        location => $_->{_links}->{self}->{href},
                        content => $_,
                    }
                } @$values ];
            }
        }
    }
    return;
}

sub clear_db{
    my($self,$data,$order_array,$collections_slice) = @_;
    $data ||= $self->data;
    $order_array //= [qw/contracts systemcontacts customercontacts/];
    my $order_hash = {};
    $collections_slice //= [keys %$data];
    @$order_hash{(keys %$data)} = (0) x @$collections_slice;
    @$order_hash{@$order_array} = (1..$#$order_array+1);
    foreach my $collection_name (sort {$order_hash->{$a} <=> $order_hash->{$b}} @$collections_slice ){
        if(!$data->{$collection_name}->{query}){
            next;
        }
        my(undef,$content) = $self->search_item($collection_name,$data);
        if($content->{total_count}){
            my $values = $content->{_links}->{$self->test_machine->get_hal_name($self->get_collection_interface($collection_name))};
            $values = ('HASH' eq ref $values) ? [$values] : $values;
            my @locations = map {$_->{href}} @$values;
            if($data->{$collection_name}->{no_delete_available}){
                @{$self->undeletable}{@locations} = ($collection_name) x @locations;
            }else{
                if($data->{$collection_name}->{delete_potentially_dependent}){
                    #no checking of deletion success will be done for items which may depend on not deletable ones
                    foreach( @locations ){
                        if(!$self->test_machine->clear_test_data_dependent($_)){
                            $self->undeletable->{$_}  = $collection_name;
                        }
                    }
                }else{
                    $self->test_machine->clear_test_data_all([ @locations ]);
                }
                $self->clear_cached_data($collection_name);
            }
        }
    }
    return;
}

sub search_item{
    my($self,$collection_name,$data) = @_;
    $data //= $self->data;
    my $item = $data->{$collection_name};
    if(!$item->{query}){
        return;
    }
    if($self->searched->{$collection_name}){
        return @{$self->searched->{$collection_name}};
    }
    my $query_string = join('&', map {
            my @deep_keys = ('ARRAY' eq ref $_) ? @$_:($_);
            my $field_name = ( @deep_keys > 1 ) ? shift @deep_keys : $deep_keys[0];
            my $spec = {};
            if('HASH' eq ref $deep_keys[0]){
                $spec = shift @deep_keys;
                @deep_keys = $spec->{field_path} ? (('ARRAY' eq $spec->{field_path}) ? @{$spec->{field_path}} : ($spec->{field_path})) : ($field_name);
            }
            #here we don't use get/set _collection_data_fields - we should refer directly to the {json}, if we have {json}
            my $search_value = deepvalue($item->{data},@deep_keys);
            if('CODE' eq ref $search_value){
                $search_value = $search_value->($self);
            }
            if($spec->{query_type} && $spec->{query_type} eq 'string_like'){
                $search_value = '%'.$search_value.'%';
            }
            $field_name.'='.uri_escape($search_value);
        } @{$item->{query}}
    );
    my($res, $content, $req) = $self->test_machine->check_item_get($self->test_machine->get_uri_get($query_string,$self->get_collection_interface($collection_name)));
    #time for memoize?
    $self->searched->{$collection_name} = [$res, $content, $req];
    return ($res, $content, $req);
}

sub clear_cached_data{
    my($self, @collections)  = @_;
    delete @{$self->loaded}{@collections};
    delete @{$self->created}{@collections};
    delete @{$self->searched}{@collections};
}

sub set_data_from_script{
    my($self, $data_in)  = @_;
    while (my($collection_name,$collection_data) = each %$data_in ){
        $self->data->{$collection_name} //= {};
        $self->data->{$collection_name} = {
            %{$self->data->{$collection_name}},
            %$collection_data,
        };
    }
    #dirty hack, part 2
    if(grep {/^load_data_only$/} @ARGV){
        no strict "vars";  ## no critic (ProhibitNoStrict)
        $data_out = $data_in;
        die;
    }
}

sub load_data_from_script{
    my($self, $collection_name)  = @_;
    my $collection_file =  dirname($0)."/api-$collection_name-collection.t";
    if(! -e $collection_file){
        $collection_file =  dirname($0)."/api-${collection_name}.t";
    }
    my $found = 0;
    if(-e $collection_file && fgrep { /set_data_from_script/ } $collection_file ){
        #dirty hack, part 1. To think about Safe
        my ($fh, $filename) = tempfile();
        local @ARGV = qw/load_data_only/;
        our $data_out;
        do $collection_file;
        if($data_out && $data_out->{$collection_name}){
            $self->data->{$collection_name} //= {};
            $self->data->{$collection_name} = $data_out->{$collection_name};
            $found = 1;
        }
    }
    if(!$found){
        die("Missed data for the $collection_name\n");
    }
}

sub load_collection_data{
    my($self, $collection_name)  = @_;
    if(!$self->data->{$collection_name}){
        $self->load_data_from_script($collection_name);
    }
    if(! ( $self->collection_id_exists($collection_name) ) ){
        if(! ( $self->keep_db_data ) ){
            $self->clear_db(undef,undef,[$collection_name]);
        }
        $self->load_db(undef,[$collection_name]);
    }
}

sub get_id{
    my $self = shift;
    #my( $collection_name, $parents_in, $params)  = @_;
    my( $collection_name )  = @_;
    $self->load_collection_data($collection_name);
    my $res_id;
    if('CODE' eq ref $self->data->{$collection_name}->{get_id}){
        $res_id = $self->data->{$collection_name}->get_id();
    }else{
        if( $self->collection_id_exists($collection_name) ){
            $res_id = $self->get_existent_id($collection_name);
        }else{
            $res_id = $self->create_get_id(@_);
        }
    }
    return $res_id;
}

sub get_field{
    my $self = shift;
    #my( $collection_name, $parents_in, $params)  = @_;
    my( $collection_name, $field )  = @_;
    $self->get_id($collection_name);
    my $item = $self->get_existent_item($collection_name);
    return $item->{content}->{$field};
}

sub get_existent_item{
    my($self, $collection_name)  = @_;
    my $item = $self->created->{$collection_name}->{values}->[0]
        || $self->loaded->{$collection_name}->[0];
    return $item
}

sub get_existent_id{
    my($self, $collection_name)  = @_;
    my $id;
    if(exists $self->created->{$collection_name}){
        $id = $self->test_machine->get_id_from_created($self->created->{$collection_name}->{values}->[0]);
    }elsif(exists $self->loaded->{$collection_name}){
        $id = $self->test_machine->get_id_from_created($self->loaded->{$collection_name}->[0]);
    }elsif(exists $self->data->{$collection_name}->{process_cycled}){
        $id = $self->data_default->{$self->data->{$collection_name}->{default}}->{id};
    }
    return $id
}

sub collection_id_exists{
    my($self, $collection_name)  = @_;
    return (exists $self->loaded->{$collection_name}) || ( exists $self->created->{$collection_name});
}

sub set_collection_data_fields{
    my($self, $collection_name, $fields)  = @_;
    @{ $self->data->{$collection_name}->{data}->{json} || $self->data->{$collection_name}->{data} }{keys %$fields} = values %$fields;
}

sub get_collection_data_fields{
    my($self, $collection_name, @fields )  = @_;
    my $data = $self->data->{$collection_name}->{data}->{json} || $self->data->{$collection_name}->{data};
    my %res = map { $_ => $data->{$_} } @fields;
    return wantarray ? %res : ( values %res )[0];
}

sub get_collection_interface{
    my($self,$collection_name,$data) = @_;
    $data //= $self->data;
    return $data->{$collection_name}->{collection} ?  $data->{$collection_name}->{collection} : $collection_name;
}

sub process{
    my($self, $collection_name, $parents_in)  = @_;
    $self->load_collection_data($collection_name);
    $parents_in //= {};
    my $parents = {%{$parents_in}};#copy
    $parents->{$collection_name}->[0] //= scalar values %$parents_in;
    while (my @keys_and_value = reach($self->data->{$collection_name}->{data})){
        my $field_value = pop @keys_and_value;
        if('CODE' eq ref $field_value ){
            $parents->{$collection_name}->[1] = [@keys_and_value];
            my $value = $field_value->($self,$parents,[@keys_and_value]);
            #here we don't use get/set _collection_data_fields - we should refer directly to the {json}, if we have {json}
            nest( $self->data->{$collection_name}->{data}, @keys_and_value, $value );
        }
    }
    return $self->data->{$collection_name}->{data};
}

sub create_get_id{
    my $self = shift;
    my $collection_name = shift;
    $self->create($collection_name,@_);
    return $self->get_existent_id($collection_name);
}

sub create{
    my($self, $collection_name, $parents_in, $params)  = @_;
    $parents_in //= {};
    $params //= {};
    if($parents_in->{$collection_name}){
        if($self->data->{$collection_name}->{default}){
            $self->data->{$collection_name}->{process_cycled} = {'parents'=>$parents_in};
            return ;
        }else{
            die('Data absence', Dumper([$collection_name,$parents_in]));
        }
    }
    $self->process($collection_name, $parents_in);
    #create itself
    my $data = clone($self->data->{$collection_name}->{data});
    if ( ref $params eq 'HASH' && ref $params->{data} eq 'HASH' && ref $params->{data}->{$collection_name} eq 'HASH' ) {
        $data = { %{$data}, %{$params->{data}->{$collection_name}} };
    }
    if ( ref $params eq 'HASH' && ref $params->{data_cb} eq 'HASH' && ref $params->{data_cb}->{$collection_name} eq 'CODE') {
        $data = $params->{data_cb}->{$collection_name}->($self, $collection_name, $data, $params);
    }
    #$self->test_machine->ssl_cert;
    my $test_machine = clone $self->test_machine;
    $test_machine->set(
        name            => $self->get_collection_interface($collection_name),
        DATA_ITEM       => $data,
    );
    my $created;
    if(exists $self->data->{$collection_name}->{create_special} && 'CODE' eq ref $self->data->{$collection_name}->{create_special}){
        $created = $self->data->{$collection_name}->{create_special}->($self,$collection_name,$test_machine);
    }else{
        $created = $test_machine->check_create_correct(1,
            $self->{use_data_callbacks}
            ?
            $self->data->{$collection_name}->{data_callbacks}->{uniquizer_cb}
            :
            undef);
    }
    $self->created->{$collection_name} = {values=>[values %{$test_machine->DATA_CREATED->{ALL}}], order => scalar keys %{$self->created}};

    if($self->data->{$collection_name}->{process_cycled}){
        #parents is a flat description of the dependency hierarchy
        #parent is just a collection which requires  id of the current collection in its data
        #parents = { $parent_collection_name => [ $number_of_parents_levels_before, [ @nested_keys in collection to set this collection value]] }
        #so, last_parent is just a collection, which directly requires current collection item id
        my $parents_cycled = $self->data->{$collection_name}->{process_cycled}->{parents};
        my $last_parent = ( sort { $parents_cycled->{$b}->[0] <=> $parents_cycled->{$a}->[0] } keys %{$parents_cycled} )[0];
        if(grep {$collection_name} @{$self->data->{$last_parent}->{dependency_requires_recreation}} ){
            undef $test_machine;
            nest( $self->data->{$last_parent}->{data}, @{$parents_cycled->{$last_parent}->[1]}, $self->get_existent_id($collection_name) );
            my %parents_temp = %{$parents_cycled};
            delete $parents_temp{$last_parent};
            #short note: we don't need update already created collections, because we fell in recursion before creation,
            #so no collection keeps wrong, redundant first item reference
            #so all we need - update "created" field for further get_existent_id, which will be called on exit from this "create" function
            $self->create($last_parent,{%parents_temp} );
        }else{
            my $uri = $test_machine->get_uri_collection($last_parent).$self->get_existent_id($last_parent);
            $test_machine->request_patch([ {
                    op   => 'replace',
                    path => join('/',('',@{$parents_cycled->{$last_parent}->[1]})),
                    value => $self->get_existent_id($collection_name) }
                ],
                $uri
            );
            undef $test_machine;
        }
        delete $self->data->{$collection_name}->{process_cycled};
    }
    return $created;
}

sub clear_test_data_all{
    my $self = shift;
    my($force_delete) = @_;
    if (!$self->test_machine) {
        return;
    }
    if($self->test_machine->cache_data && !$force_delete){
       store {loaded => $self->loaded, created => $self->created}, $self->data_cache_file;
    }else{
        if( 'HASH' eq ref $self->created ) {
            $self->test_machine->clear_test_data_all(
                [
                    map {
                        $_->{location}
                    }
                    map {
                        @{$self->{created}->{$_}->{values}}
                    }
                    sort{
                        $self->{created}->{$b}->{order} <=> $self->{created}->{$a}->{order}
                    }
                    grep {
                        !$self->{data}->{$_}->{no_delete_available}
                    }
                    (keys %{$self->created})
                ]
            );
        }
    }
}

sub read_cached_data{
    my $self = shift;
    if(! -e $self->data_cache_file ){
        return;
    }
    my $restored = retrieve($self->data_cache_file);
    my $clear_cached_from_deleted = sub {
        my $cached_collections = shift;
        foreach my $cached_collection(keys %{$cached_collections}){
            foreach my $deleted_uri(keys %{$restored->{deleted}->{204}}){
                if(index($cached_collections->{$cached_collection}->{location},$deleted_uri) || index($deleted_uri,$cached_collections->{$cached_collection}->{location})){
                    delete $cached_collections->{$cached_collection};
                }
            }
        }
    };
    $clear_cached_from_deleted->($restored->{loaded});
    $clear_cached_from_deleted->($restored->{created});
    $self->loaded($restored->{loaded} // {} );
    $self->created($restored->{created} // {} );
    #delete $restored->{deleted};
    store {loaded => $self->loaded, created => $self->created}, $self->data_cache_file;
}


sub string_uniquizer{
    my($field,$data,$additions) = @_;
    state $i;
    $i++;
    $additions //= '';
    if(ref $field){
        $$field = $$field.time().$i.$additions;
    }else{
        $field = $field.time().$i.$additions;
    }
    return $field;
}

sub get2put_upload_callback{
    my($self,$collection_name) = @_;
     return sub {
        my($data,$data_add,$test_machine) = @_;
        my $upload_data = clone $self->data->{$collection_name}->{data};
        delete $upload_data->{json};
        %$data = ( 
            'json' => {%$data},
            %$upload_data,
        ); 
    };
}

sub DEMOLISH{
    my($self) = @_;
    $self->clear_test_data_all();
    if( keys %{$self->undeletable} ){
        print "We have test items, which can't delete through API:\n";
        print Dumper [ sort { $a cmp $b } keys %{$self->undeletable} ];
    }
}

sub seq{
    my ($number) = @_;
    state $seq = 0;
    $number //= 0;
    return $number + $seq++;
}

1;

__END__

Further improvements:
Really it would be much more correct to use collection clases with ALL their own test machine initialization for data creation. just will call proper collection class. It will allow to keep data near releveant tests, and don't duplicate test_machine params in the FakeData.

Optimizations:
1.make wrapper for data creation/deletion for all tests.
2.Load/Clear only relevant tests data
