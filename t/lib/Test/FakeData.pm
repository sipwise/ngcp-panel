package Test::FakeData;

use strict;

use Sipwise::Base;
use Test::Collection;
use JSON;
use Test::More;
use File::Basename;
use Data::Dumper;
use Test::DeepHashUtils qw(reach nest deepvalue);
use Clone qw/clone/;

has 'test_machine' =>(
    is => 'rw',
    isa => 'Test::Collection',
    default => sub { Test::Collection->new () },
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
has 'FLAVOUR' => (
    is => 'rw',
    isa => 'Str',
);
#TODO: optimization - pre load and predelete should be done only for required collections and dependencies
has 'work_collections' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
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
                reseller_id => sub { return shift->create('resellers',@_); },
            },
            'query' => ['email'],
            'delete_potentially_dependent' => 1,
        },
        'contracts'   => {
            'data' => {
                contact_id         => sub { return shift->create('systemcontacts',@_); },
                status             => 'active',
                external_id        => 'api_test',
                #type               => sub { return value_request('contracts','type',['reseller']); },
                type               => 'reseller',
                billing_profile_id => sub { return shift->create('billingprofiles',@_); },
            },
            'default' => 'contracts',
            'query' => ['external_id'],
            'no_delete_available' => 1,
        },
        'resellers' => {
            'data' => {
                contract_id => sub { return shift->create('contracts', @_ ); },
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
                contact_id         => sub { return shift->create('customercontacts',@_); },
                billing_profile_id => sub { return shift->create('billingprofiles',@_); },
                max_subscribers    => undef,
                external_id        => 'api_test customer',
                type               => 'pbxaccount',#sipaccount
            },
            'query' => ['external_id'],
            'no_delete_available' => 1,
        },
        'billingprofiles' => {
            'data' => {
                name        => 'api_test test profile',
                handle      => 'api_test_testprofile',
                reseller_id => sub { return shift->create('resellers',@_); },
            },
            'default' => 'billing_profiles',
            'query' => ['handle'],
            'no_delete_available' => 1,
        },
        'subscribers' => {
            'data' => {
                administrative       => 0,
                customer_id          => sub { return shift->create('customers',@_); },
                primary_number       => { ac => 111, cc=> 111, sn => 111 },
                alias_numbers        => [ { ac => 11, cc=> 11, sn => 11 } ],
                username             => 'api_test_username',
                password             => 'api_test_password',
                webusername          => 'api_test_webusername',
                webpassword          => undef,
                domain_id            => sub { return shift->create('domains',@_); },,
                #domain_id            =>
                email                => undef,
                external_id          => undef,
                is_pbx_group         => 1,
                is_pbx_pilot         => 1,
                pbx_extension        => '111',
                pbx_group_ids        => [],
                pbx_groupmember_ids  => [],
                profile_id           => sub { return shift->create('subscriberprofiles',@_); },
                status               => 'active',
                pbx_hunt_policy      => 'parallel',
                pbx_hunt_timeout     => '15',
            },
            'query' => ['username'],
        },
        'domains' => {
            'data' => {
                domain => 'api_test_domain.api_test_domain',
                reseller_id => sub { return shift->create('resellers',@_); },
            },
            'query' => ['domain'],
        },
        'subscriberprofilesets' => {
            'data' => {
                name        => 'api_test_subscriberprofileset',
                reseller_id => sub { return shift->create('resellers',@_); },
                description => 'api_test_subscriberprofileset',
            },
            'query' => ['name'],
        },
        'subscriberprofiles' => {
            'data' => {
                name           => 'api_test subscriberprofile',
                profile_set_id => sub { return shift->create('subscriberprofilesets',@_); },
                description    => 'api_test subscriberprofile',
            },
            'query' => ['name'],
        },
        'pbxdevicemodels' => {
            'data' => {
                json => {
                    model       => "api_test ATA111",
                    #reseller_id=1 is very default, as is seen from the base initial script
                    #reseller_id => "1",
                    reseller_id => sub { return shift->create('resellers',@_); },
                    vendor      =>"Cisco",
                    #3.7relative tests
                    type               => "phone",
                    connectable_models => [],
                    extensions_num     => "2",
                    bootstrap_method   => "http",
                    bootstrap_uri      => "",
                    bootstrap_config_http_sync_method            => "GET",
                    bootstrap_config_http_sync_params            => "[% server.uri %]/\$MA",
                    bootstrap_config_http_sync_uri               => "http=>//[% client.ip %]/admin/resync",
                    bootstrap_config_redirect_panasonic_password => "",
                    bootstrap_config_redirect_panasonic_user     => "",
                    bootstrap_config_redirect_polycom_password   => "",
                    bootstrap_config_redirect_polycom_profile    => "",
                    bootstrap_config_redirect_polycom_user       => "",
                    bootstrap_config_redirect_yealink_password   => "",
                    bootstrap_config_redirect_yealink_user       => "",
                    #TODO:implement checking against this number in the controller and api
                    #/3.7relative tests
                    "linerange"=>[
                        {
                            "keys" => [
                                {y => "390", labelpos => "left", x => "510"},
                                {y => "350", labelpos => "left", x => "510"}
                            ],
                            can_private => "1",
                            can_shared  => "0",
                            can_blf     => "0",
                            name        => "Phone Ports api_test",
                            #TODO: test duplicate creation #"id"=>1311,
                        },
                        {
                            "keys"=>[
                                {y => "390", labelpos => "left", x => "510"},
                                {y => "350", labelpos => "left", x => "510"}
                            ],
                            can_private => "1",
                            can_shared  => "0",
                            #TODO: If I'm right - now we don't check field values against this, because test for pbxdevice xreation is OK
                            can_blf     => "0",
                            name        => "Extra Ports api_test",
                            #TODO: test duplicate creation #"id"=>1311,
                        }
                    ]
                },
                #TODO: can check big files
                #front_image => [ dirname($0).'/resources/api_devicemodels_front_image.jpg' ],
                front_image => [ dirname($0).'/resources/empty.txt' ],
            },
            'query' => [ ['model','json','model'] ],
            'create_special'=> sub {
                my ($self,$name) = @_;
                my $prev_params = $self->test_machine->get_cloned('content_type');
                @{$self->test_machine->content_type}{qw/POST PUT/} = (('multipart/form-data') x 2);
                $self->test_machine->check_create_correct(1);
                $self->test_machine->set(%$prev_params);
            },
            'no_delete_available' => 1,
        },
        'pbxdeviceconfigs' => {
            'data' => {
                device_id    => sub { return shift->create('pbxdevicemodels',@_); },
                version      => 'api_test 1.1',
                content_type => 'text/plain',
            },
            'query' => ['version'],
            'create_special'=> sub {
                my ($self,$name) = @_;
                my $prev_params = $self->test_machine->get_cloned('content_type','QUERY_PARAMS');
                $self->test_machine->content_type->{POST} = $self->data->{$name}->{data}->{content_type};
                $self->test_machine->QUERY_PARAMS($self->test_machine->hash2params($self->data->{$name}->{data}));
                $self->test_machine->check_create_correct(1, sub {return 'test_api_empty_config';} );
                $self->test_machine->set(%$prev_params);
            },
            'no_delete_available' => 1,
        },
        'pbxdeviceprofiles' => {
            'data' => {
                config_id    => sub { return shift->create('pbxdeviceconfigs',@_); },
                name         => 'api_test profile 1.1',
            },
            'query' => ['name'],
            'no_delete_available' => 1,
        },
        'pbxdevices' => {
            'data' => {
                profile_id   => sub { return shift->create('pbxdeviceprofiles',@_); },
                customer_id  => sub { return shift->create('customers',@_); },
                identifier   => 'aaaabbbbcccc',
                station_name => 'api_test_vun',
                lines=>[{
                    linerange      => 'Phone Ports api_test',
                    type           => 'private',
                    key_num        => '0',
                    subscriber_id  => sub { return shift->create('subscribers',@_); },
                    extension_unit => '1',
                    extension_num  => '1',#to handle some the same extensions devices
                    },{
                    linerange      => 'Extra Ports api_test',
                    type           => 'blf',
                    key_num        => '1',
                    subscriber_id  => sub { return shift->create('subscribers',@_); },
                    extension_unit => '2',
                }],
            },
            'query' => ['station_name'],
        },
    };
    foreach my $collection_name( keys %$data ){
        if($self->FLAVOUR && exists $data->{$collection_name}->{flavour} && exists $data->{$collection_name}->{flavour}->{$self->FLAVOUR}){
            $data = {%$data, %{$data->{$collection_name}->{flavour}->{$self->FLAVOUR}}},
        }
    }
    $self->clear_db($data,[qw/contracts systemcontacts customercontacts/]);
    #incorrect place, leave it for the next timeframe to work on it
    $self->load_db($data);
    return $data;
}
sub load_db{
    my($self,$data) = @_;
    $data //= $self->data;
    foreach my $collection_name( keys %$data ){
        #print "collection_name=$collection_name;\n";
        if((!exists $self->loaded->{$collection_name}) && $data->{$collection_name}->{query}){
            my(undef,$content) = $self->search_item($collection_name,$data);
            if($content->{total_count}){
                my $values = $content->{_embedded}->{$self->test_machine->get_hal_name};
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
    my($self,$data,$order_array) = @_;
    $order_array //= [];
    my $order_hash = {};
    @$order_hash{(keys %$data)} = (0) x (keys %$data);
    @$order_hash{@$order_array} = (1..$#$order_array+1);
    my @undeletable_items = ();
    foreach my $collection_name (sort {$order_hash->{$a} <=> $order_hash->{$b}} keys %$data ){
        if((!$data->{$collection_name}->{query})){
            next;
        }
        my(undef,$content) = $self->search_item($collection_name,$data);
        if($content->{total_count}){
            my $values = $content->{_links}->{$self->test_machine->get_hal_name};
            $values =
            ('HASH' eq ref $values) ? [$values] : $values;
            my @locations = map {$_->{href}} @$values;
            if($data->{$collection_name}->{no_delete_available}){
                push @undeletable_items, @locations;
            }else{
                if($data->{$collection_name}->{delete_potentially_dependent}){
                    foreach( @locations ){
                        if(!$self->test_machine->clear_test_data_dependent($_)){
                            push @undeletable_items, $_;
                        }
                    }
                }else{
                    $self->test_machine->clear_test_data_all([ @locations ]);
                }
            }
        }
    }
    if(@undeletable_items){
        print "We have test items, which can't delete through API:\n";
        print Dumper [ @undeletable_items ];
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
    $self->test_machine->name($collection_name);
    my $query_string = join('&', map {
            my @deep_keys = ('ARRAY' eq ref $_) ? @$_:($_);
            my $field_name = ( @deep_keys > 1 ) ? shift @deep_keys : $deep_keys[0];
            $field_name.'='.deepvalue($item->{data},@deep_keys);
        } @{$item->{query}}
    );
    my($res, $content, $req) = $self->test_machine->check_item_get($self->test_machine->get_uri_get($query_string));
    return ($res, $content, $req);
}
sub create{
    my($self, $name, $parents_in, $field_path, $params)  = @_;
    $parents_in //= {};
    if($self->loaded->{$name} || $self->created->{$name}){
        return $self->get_id($name);
    }
    if($parents_in->{$name}){
        if($self->data->{$name}->{default}){
            $self->data->{$name}->{process_cycled} = {'parents'=>$parents_in,'field_path'=>$field_path};
            return $self->data_default->{$self->data->{$name}->{default}}->{id};
        }else{
            die('Data absence', Dumper([$name,$parents_in]));
        }
    }
    $self->process($name, $parents_in);
    #create itself
    my $data = clone($self->data->{$name}->{data});
    $self->test_machine->set(
        name            => $name,
        DATA_ITEM       => $data,
    );
    if(exists $self->data->{$name}->{create_special} && 'CODE' eq ref $self->data->{$name}->{create_special}){
        $self->data->{$name}->{create_special}->($self,$name);
    }else{
        $self->test_machine->check_create_correct(1);
    }
    $self->created->{$name} = [values %{$self->test_machine->DATA_CREATED->{ALL}}];

    if($self->data->{$name}->{process_cycled}){
        my %parents_cycled_ordered = reverse %{$self->data->{$name}->{process_cycled}->{parents}};
        my $last_parent = -1 + ( scalar values (%parents_cycled_ordered) );
        my $uri = $self->test_machine->get_uri_collection($parents_cycled_ordered{$last_parent}).$self->get_id($parents_cycled_ordered{$last_parent});
        $self->test_machine->request_patch([ {
            op   => 'replace',
            path => join('/',('',@{$self->data->{$name}->{process_cycled}->{field_path}})),
            value => $self->get_id($name) } ],
            $uri
        );
        delete $self->data->{$name}->{process_cycled};
    }
    return $self->get_id($name);
}

sub process{
    my($self, $name, $parents_in)  = @_;
    $parents_in //= {};
    my $parents = {%{$parents_in}};
    $parents->{$name} //= scalar values %$parents_in;
    while (my @keys_and_value = reach($self->data->{$name}->{data})){
        my $field_value = pop @keys_and_value;
        if('CODE' eq ref $field_value ){
            my $value = $field_value->($self,$parents,[@keys_and_value]);
            nest( $self->data->{$name}->{data}, @keys_and_value, $value );
        }
    }
    return $self->data->{$name}->{data};
}
sub get_id{
    my($self, $name)  = @_;
    my $id = $self->test_machine->get_id_from_created($self->created->{$name}->[0])
        || $self->test_machine->get_id_from_created($self->loaded->{$name}->[0]);
    return $id
}
sub DEMOLISH{
    my($self) = @_;
    ( 'ARRAY' eq ref$self->created ) and ( $self->test_machine->clear_test_data_all([ map {$_->{location}} @$self->created ]) );
}
1;
__END__

Further improvements:
Really it would be much more correct to use collection clases with ALL their own test machine initialization for data creation. just will call proper collection class. It will allow to keep data near releveant tests, and don't duplicate test_machine params in the FakeData.

Optimizations:
1.make wrapper for data creation/deletion for all tests.
2.Load/Clear only relevant tests data

