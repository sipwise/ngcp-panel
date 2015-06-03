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
use File::Slurp qw/read_file/;

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
        },
        'billingprofiles' => {
            'data' => {
                name        => 'api_test test profile',
                handle      => 'api_test_testprofile',
                reseller_id => sub { return shift->get_id('resellers',@_); },
            },
            'default' => 'billing_profiles',
            'query' => ['handle'],
            'no_delete_available' => 1,
        },
        'subscribers' => {
            'data' => {
                administrative       => 0,
                customer_id          => sub { return shift->get_id('customers',@_); },
                primary_number       => { ac => 111, cc=> 111, sn => 111 },
                alias_numbers        => [ { ac => 11, cc=> 11, sn => 11 } ],
                username             => 'api_test_username',
                password             => 'api_test_password',
                webusername          => 'api_test_webusername',
                webpassword          => undef,
                domain_id            => sub { return shift->get_id('domains',@_); },,
                #domain_id            =>
                email                => undef,
                external_id          => undef,
                is_pbx_group         => 1,
                is_pbx_pilot         => 1,
                pbx_extension        => '111',
                pbx_group_ids        => [],
                pbx_groupmember_ids  => [],
                profile_id           => sub { return shift->get_id('subscriberprofiles',@_); },
                status               => 'active',
                pbx_hunt_policy      => 'parallel',
                pbx_hunt_timeout     => '15',
            },
            'query' => ['username'],
        },
        'domains' => {
            'data' => {
                domain => 'api_test_domain.api_test_domain',
                reseller_id => sub { return shift->get_id('resellers',@_); },
            },
            'query' => ['domain'],
        },
        'subscriberprofilesets' => {
            'data' => {
                name        => 'api_test_subscriberprofileset',
                reseller_id => sub { return shift->get_id('resellers',@_); },
                description => 'api_test_subscriberprofileset',
            },
            'query' => ['name'],
        },
        'subscriberprofiles' => {
            'data' => {
                name           => 'api_test subscriberprofile',
                profile_set_id => sub { return shift->get_id('subscriberprofilesets',@_); },
                description    => 'api_test subscriberprofile',
            },
            'query' => ['name'],
        },
        'pbxdeviceconfigs' => {
            'data' => {
                device_id    => sub { return shift->get_id('pbxdevicemodels',@_); },
                version      => 'api_test 1.1',
                content_type => 'text/plain',
            },
            'query' => ['version'],
            'create_special'=> sub {
                my ($self,$collection_name) = @_;
                my $prev_params = $self->test_machine->get_cloned('content_type','QUERY_PARAMS');
                $self->test_machine->content_type->{POST} = $self->data->{$collection_name}->{data}->{content_type};
                $self->test_machine->QUERY_PARAMS($self->test_machine->hash2params($self->data->{$collection_name}->{data}));
                $self->test_machine->check_create_correct(1, sub {return 'test_api_empty_config';} );
                $self->test_machine->set(%$prev_params);
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
        },
    };
    #$self->process_data($data);
    return $data;
}
sub process_data{
    my($self,$data,$collections_slice) = @_;
    $collections_slice //= [keys %$data];
    foreach my $collection_name( @$collections_slice ){
        if($self->FLAVOUR && exists $data->{$collection_name}->{flavour} && exists $data->{$collection_name}->{flavour}->{$self->FLAVOUR}){
            $data = {%$data, %{$data->{$collection_name}->{flavour}->{$self->FLAVOUR}}},
        }
    }
    $self->clear_db($data);
    #incorrect place, leave it for the next timeframe to work on it
    $self->load_db($data);
}
sub load_db{
    my($self,$data,$collections_slice) = @_;
    $data //= $self->data;
    $collections_slice //= [keys %$data];
    foreach my $collection_name( @$collections_slice ){
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
    my($self,$data,$order_array,$collections_slice) = @_;
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
            my $values = $content->{_links}->{$self->test_machine->get_hal_name};
            $values = ('HASH' eq ref $values) ? [$values] : $values;
            my @locations = map {$_->{href}} @$values;
            if($data->{$collection_name}->{no_delete_available}){
                @{$self->undeletable->{@locations}} = ($collection_name) x @locations;
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
    $self->test_machine->name($collection_name);
    my $query_string = join('&', map {
            my @deep_keys = ('ARRAY' eq ref $_) ? @$_:($_);
            my $field_name = ( @deep_keys > 1 ) ? shift @deep_keys : $deep_keys[0];
            my $search_value = deepvalue($item->{data},@deep_keys);
            if('CODE' eq ref $search_value){
                $search_value = $search_value->($self);
            }
            $field_name.'='.$search_value;
        } @{$item->{query}}
    );
    my($res, $content, $req) = $self->test_machine->check_item_get($self->test_machine->get_uri_get($query_string));
    #time for memoize?
    $self->searched->{$collection_name} = [$res, $content, $req];
    return ($res, $content, $req);
}

sub set_data_from_script{
    my($self, $data_in)  = @_;
    #$self->data->{$collection_name}->{data} = $data;
    while (my($collection_name,$collection_data) = each %$data_in ){
        $self->data->{$collection_name} //= {};
        $self->data->{$collection_name} = {
            %{$self->data->{$collection_name}},
            %$collection_data,
        };
    }
    #dirty hack, part 2
    if(grep {/^load_data_only$/} @ARGV){
        no strict "vars";
        $data_out = $data_in;
        die;
    }
}

sub load_data_from_script{
    my($self, $collection_name)  = @_;
    my $collection_file =  "./api-$collection_name.t";
    my $found = 0;
    if(-e $collection_file){
        #dirty hack, part 1. To think about Safe
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

sub process{
    my($self, $collection_name, $parents_in)  = @_;
    $self->load_collection_data($collection_name);
    $parents_in //= {};
    my $parents = {%{$parents_in}};
    $parents->{$collection_name} //= scalar values %$parents_in;
    while (my @keys_and_value = reach($self->data->{$collection_name}->{data})){
        my $field_value = pop @keys_and_value;
        if('CODE' eq ref $field_value ){
            my $value = $field_value->($self,$parents,[@keys_and_value]);
            nest( $self->data->{$collection_name}->{data}, @keys_and_value, $value );
        }
    }
    return $self->data->{$collection_name}->{data};
}
sub load_collection_data{
    my($self, $collection_name)  = @_;
    if(!$self->data->{$collection_name}){
        $self->load_data_from_script($collection_name);
    }
    if(!$self->collection_id_exists($collection_name) ){
        $self->clear_db(undef,undef,[$collection_name]);
        $self->load_db(undef,[$collection_name]);
    }
}
sub get_id{
    my $self = shift;
    #my( $collection_name, $parents_in, $field_path, $params)  = @_;
    my( $collection_name )  = @_;
    $self->load_collection_data($collection_name);
    if( $self->collection_id_exists($collection_name) ){
        return $self->get_existent_id($collection_name);
    }
    return $self->create(@_);
}

sub get_existent_id{
    my($self, $collection_name)  = @_;
    my $id = $self->test_machine->get_id_from_created($self->created->{$collection_name}->[0])
        || $self->test_machine->get_id_from_created($self->loaded->{$collection_name}->[0]);
    return $id
}

sub create{
    my($self, $collection_name, $parents_in, $field_path, $params)  = @_;
    $parents_in //= {};
    if($parents_in->{$collection_name}){
        if($self->data->{$collection_name}->{default}){
            $self->data->{$collection_name}->{process_cycled} = {'parents'=>$parents_in,'field_path'=>$field_path};
            return $self->data_default->{$self->data->{$collection_name}->{default}}->{id};
        }else{
            die('Data absence', Dumper([$collection_name,$parents_in]));
        }
    }
    $self->process($collection_name, $parents_in);
    #create itself
    my $data = clone($self->data->{$collection_name}->{data});
    $self->test_machine->set(
        name            => $collection_name,
        DATA_ITEM       => $data,
    );
    if(exists $self->data->{$collection_name}->{create_special} && 'CODE' eq ref $self->data->{$collection_name}->{create_special}){
        $self->data->{$collection_name}->{create_special}->($self,$collection_name);
    }else{
        $self->test_machine->check_create_correct(1);
    }
    $self->created->{$collection_name} = [values %{$self->test_machine->DATA_CREATED->{ALL}}];

    if($self->data->{$collection_name}->{process_cycled}){
        my %parents_cycled_ordered = reverse %{$self->data->{$collection_name}->{process_cycled}->{parents}};
        my $last_parent = -1 + ( scalar values (%parents_cycled_ordered) );
        my $uri = $self->test_machine->get_uri_collection($parents_cycled_ordered{$last_parent}).$self->get_existent_id($parents_cycled_ordered{$last_parent});
        $self->test_machine->request_patch([ {
            op   => 'replace',
            path => join('/',('',@{$self->data->{$collection_name}->{process_cycled}->{field_path}})),
            value => $self->get_existent_id($collection_name) } ],
            $uri
        );
        delete $self->data->{$collection_name}->{process_cycled};
    }
    return $self->get_existent_id($collection_name);
}

sub collection_id_exists{
    my($self, $collection_name)  = @_;
    return exists $self->loaded->{$collection_name} || exists $self->created->{$collection_name}
}
sub DEMOLISH{
    my($self) = @_;
    ( 'ARRAY' eq ref $self->created ) and ( $self->test_machine->clear_test_data_all([ map {$_->{location}} @$self->created ]) );
    if( keys %{$self->undeletable} ){
        print "We have test items, which can't delete through API:\n";
        print Dumper [ sort { $a cmp $b } keys %{$self->undeletable} ];
    }

}
1;
__END__

Further improvements:
Really it would be much more correct to use collection clases with ALL their own test machine initialization for data creation. just will call proper collection class. It will allow to keep data near releveant tests, and don't duplicate test_machine params in the FakeData.

Optimizations:
1.make wrapper for data creation/deletion for all tests.
2.Load/Clear only relevant tests data

