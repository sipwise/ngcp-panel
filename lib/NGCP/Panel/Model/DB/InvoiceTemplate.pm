package NGCP::Panel::Model::DB::InvoiceTemplate;
use base NGCP::Panel::Model::DB::Base;

#use irka;
use Data::Dumper;

sub getDefaultConditions{
    my $self = shift;
    my ($params) = @_;
    #irka::loglong(Dumper($params));
    my ($provider_id,$tt_sourcestate,$tt_type,$tt_id) = @$params{qw/provider_id tt_sourcestate tt_type tt_id/};
    my $conditions = {};
    #irka::loglong("getDefaultConditions: tt_id=$tt_id;\n");
    if($tt_id){
        $conditions = { id => $tt_id };
    }else{
        $conditions = {
            reseller_id => $provider_id,
            type        => $tt_type,
            is_active   => 1,
        };
    }
    return $conditions;
}
sub getInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id,$tt_sourcestate,$tt_type,$tt_id) = @params{qw/provider_id tt_sourcestate tt_type tt_id/};

    #irka::loglong("getInvoiceTemplate: tt_id=$tt_id;\n");
    #irka::loglong(Dumper(\%params));
    my $result = '';
    
    my $conditions = $self->getDefaultConditions(\%params);
    #my $tt_record = $self->resultset('invoice_templates')->search({
    #it is hard to express my disappointment by DBIx implementation. Where pure SQL is easy to automate, flexible and powerful, with DBIx you can't even get DB as aliases, only additional accessors, which aren't a option. What a poor "wonabe hibernate" idea and implementation.
    my $tt_record = $self->schema->resultset('invoice_templates')->search( 
        { id => $tt_id }, {
        #'+select' => [{'reseller_id' =>'provider_id','-as'=>'provider_id'},{'id' => 'tt_id','-as'=>'tt_id'}]
        #'+select' => [
        #    [ 'reseller_id', {'-as'=>'provider_id'}],
        #    [ 'id', {'-as'=>'tt_id'}],
        #],
        #'+select' => [qw/reseller_id id/],
        #'+as'     => [qw/provider_id tt_id/]
        #'-as'     => [{reseller_id=>provider_id},{ id=>tt_id}]
    }
    )->first;
    #here may be base64 decoding
    
    #here we will rely on form checking and defaults
    #if('saved' eq $tt_sourcestate){
    if( $tt_record ){
        $tt_sourcestate and $result = $tt_record->get_column( 'base64_'.$tt_sourcestate );
        #$tt_record->reseller_id
        $tt_id = $tt_record->get_column( 'id' );
    }
    if( $result && exists $params{result} ){
        ${$params{result}} = $result;
    }
    return ( $tt_id, \$result, $tt_record );#tt_record - sgorila hata, gori i saray
}

sub storeInvoiceTemplateContent{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id, $tt_sourcestate, $tt_type,$tt_string,$tt_id,$is_active,$name) = @params{qw/provider_id tt_sourcestate tt_type tt_string_sanitized tt_id is_active name/};

    #my $tt_record = $self->resultset('invoice_templates')->search({
    $self->schema->txn_do(sub {
#reseller_id and is_active aren't unique key, because is_active can kepp some 0 values for one reseller, we shouldn't keep active and inactive in one table
#        $self->schema->resultset('invoice_templates')->update_or_create({
#            reseller_id => $provider_id,
#            type        => $tt_type,
#            is_active   => 1,
#            'base64_'.$tt_sourcestate => $$tt_string,
#        });


        #here may be base64 decoding

#        $self->schema->resultset('ivoice_template')->search({
#            reseller_id => $provider_id,
#            type        => $tt_type,
#        })->update_all({
#            is_active   => 0,
#        });
        #I think that SQl + DBI are much more flexible and compact 
        my $tt_record_created;
        my $tt_record_updated;
        if( !$tt_id ){
            $tt_record_created = $self->schema->resultset('invoice_templates')->create({
                reseller_id => $provider_id,
                type        => $tt_type,
#                is_active   => $is_active,
#                name        => $name,
                'base64_'.$tt_sourcestate => $$tt_string,
            });
            if($tt_record_created){
                $tt_id = $tt_record_created->id();
            }
        }else{
            my $conditions = $self->getDefaultConditions(\%params);
            $tt_record_updated = $self->schema->resultset('invoice_templates')->search($conditions);
            $tt_record_updated->update({
#                is_active   => $is_active,
#                name        => $name,
                'base64_'.$tt_sourcestate => $$tt_string,
            });
        }
#        if($is_active && $tt_id){
#            $self->deactivateOtherTemplates($provider_id,$tt_id);
#        }
    });
    return { tt_id => $tt_id };
}
sub storeInvoiceTemplateInfo{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id,$tt_id,$is_active,$name) = @params{qw/provider_id tt_id is_active name/};

    #my $tt_record = $self->resultset('invoice_templates')->search({
    $self->schema->txn_do(sub {
        my $tt_record_created;
        my $tt_record_updated;
        if( !$tt_id ){
            $tt_record_created = $self->schema->resultset('invoice_templates')->create({
                reseller_id => $provider_id,
                is_active   => $is_active,
                name        => $name,
            });
            if($tt_record_created){
                $tt_id = $tt_record_created->id();
            }
        }else{
            $tt_record_updated = $self->schema->resultset('invoice_templates')->search({ id => $tt_id });
            $tt_record_updated->update({
                is_active   => $is_active,
                name        => $name,
            });
        }
        if($is_active && $tt_id){
            $self->deactivateOtherTemplates($provider_id,$tt_id);
        }
    });
    return { tt_id => $tt_id };
}
sub getInvoiceTemplateList{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id,$tt_sourcestate,$tt_type, $tt_string, $tt_id) = @params{qw/provider_id tt_sourcestate tt_type tt_string_sanitized tt_id/};
    
    #return [
        #$self->schema->resultset('invoice_template_fake')->find(\'select * from invoice_templates')->all
        #$self->schema->resultset('invoice_templates')->name(\'(select * from invoice_templates)')->all
    #];
    return $self->schema->resultset('invoice_templates')->search({
        reseller_id => $provider_id,
    });
}
sub deleteInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id, $tt_id) = @params{qw/provider_id tt_id/};
    return $self->schema->resultset('invoice_templates')->search({
        reseller_id => $provider_id,
        id => $tt_id,
    })->delete_all;
}
sub activateInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id, $tt_id) = @params{qw/provider_id tt_id/};
    $self->schema->txn_do(sub {
        $self->schema->resultset('invoice_templates')->search({
            reseller_id => $provider_id,
            id => $tt_id,
        })->update({
            is_active => 1,
        });
        $self->deactivateOtherTemplates($provider_id,$tt_id);
     });
}
sub deactivateInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id, $tt_id) = @params{qw/provider_id tt_id/};
    $self->schema->txn_do(sub {
        $self->schema->resultset('invoice_templates')->search({
            reseller_id => $provider_id,
            id => $tt_id,
        })->update({
            is_active => 0,
        });
     });
}
sub deactivateOtherTemplates{
    my $self = shift;
    my ($provider_id,$tt_id) = @_;
    $self->schema->resultset('invoice_templates')->search({
        reseller_id => $provider_id,
        id          => {'!=' => $tt_id },
        is_active   => 1,
    })->update_all({
        is_active => 0,
    });
}
sub checkInvoiceTemplateProvider{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id,$tt_id) = @params{qw/provider_id tt_id/};
    my $tt_record = $self->schema->resultset('invoice_templates')->search({
        reseller_id => $provider_id,
        id => $tt_id,
    });
    if($tt_record->get_column('id')){
        return 1;
    }
    return 0;
}

sub getInvoiceClientContactInfo{
    my $self = shift;
    my (%params) = @_;
    my ($client_id) = @params{qw/client_id/};
    return $tt_record = $self->schema->resultset('invoice_templates')->search({
        reseller_id => $client_id,
    });
}

sub getInvoiceProviderClients{
    my $self = shift;
    my (%params) = @_;
    my ($provider_id) = @params{qw/provider_id/};
    #$schema->resultset('contracts')
#    my $mapping_rs = $schema->resultset('billing_mappings');
#    my $rs = $schema->resultset('contracts')
#        ->search({
#            'me.status' => { '!=' => 'terminated' },
#            'billing_mappings.id' => {
#                '=' => $mapping_rs->search({
#                    contract_id => { -ident => 'me.id' },
#                    start_date => [ -or =>
#                        { '<=' => NGCP::Panel::Utils::DateTime::current_local },
#                        { -is  => undef },
#                    ],
#                    end_date => [ -or =>
#                        { '>=' => NGCP::Panel::Utils::DateTime::current_local },
#                        { -is  => undef },
#                    ],
#                },{
#                    alias => 'bilmap',
#                    rows => 1,
#                    order_by => {-desc => ['bilmap.start_date', 'bilmap.id']},
#                })->get_column('id')->as_query,
#            },
#        },{
#            'join' => 'billing_mappings',
#            '+select' => [
#                'billing_mappings.id',
#                'billing_mappings.start_date',
#                'billing_mappings.product_id',
#            ],
#            '+as' => [
#                'billing_mapping_id',
#                'billing_mapping_start_date',
#                'product_id',
#            ],
#            alias => 'me',
#        });
#
#    return $rs;


    #very optimistic programming style

    return NGCP::Panel::Utils::Contract::get_contract_rs(
            schema => $self->schema,
        )->search_rs({
            'contact.reseller_id' => $provider_id,
        },{
            join => 'contact',
    });
}

sub get_contract_calls_rs{
    my $self = shift;
    my %params = @_;
    (my($c,$provider_id,$client_id,$stime,$etime)) = @params{qw/c provider_id client_id stime etime/};
    my $source_account_id_condition;
    if(!$client_id){
        $source_account_id_condition = { 'in' => $self->getInvoiceProviderClients(%params)->search_rs({},{
                'select' => 'me.id',
            })->as_query()
            #$self->schema('contracts')->search_rs({},{
            #    'select' => 'me.id',
            #    'join'   => 'contact',
            #})->as_query() 
        };
    }else{
        $source_account_id_condition = $client_id;
    }
    $sql = '
    select cdr.* from accounting.cdr 
        inner join contracts on cdr.source_account_id=contracts.id
            and contracts.status != "terminated"
        inner join contacts on contracts.contact_id=contacts.id 
            and contacts.reseller_id=1 and contacts.reseller_id!=contacts.id 
    where
        cdr.source_user_id != 0
        and cdr.call_status="ok" 
        and exists (select * 
            from billing_mappings
            inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
            where contracts.id=billing_mappings.contract_id
                and (billing_mappings.start_date >= now() OR start_date IS NULL)
                and (billing_mappings.end_date <= now() OR end_date IS NULL)
        )
        order by cdr.start_time
        ';
    my $calls_rs = $self->schema->resultset('cdr')->search( {
#        source_user_id => { 'in' => [ map {$_->uuid} @{$contract->{subscriber}} ] },
        'call_status'       => 'ok',
        'source_user_id'    => { '!=' => '0' },
        'contact.id'        => { '!=' => $provider_id },
        '-and'              => [ 
            #'contact.reseller_id' => $provider_id, 
            'contact.reseller_id' => { '!=' => undef },
        ],
        'source_account.status'    => { '!=' => 'terminated'},
        '-exists'           => $self->schema->resultset('billing_mappings')->search({
            'contract_id' => \'= source_account.id',
            'product.class' => [ "sipaccount", "pbxaccount" ],
        },{
            alias => 'billing_mappings_top',
            join => 'product',
        })->as_query,
    },{
        '+select' => [
            'source_customer_billing_zones_history.zone', 
            'source_customer_billing_zones_history.detail', 
            'destination_user_in',
        ],
        '+as'  => [qw/zone zone_detail destination/],
        'join' => [
            {
                'source_account' => 'contact',
            },
            'source_customer_billing_zones_history', 
        ]
    } );    
    
    return $calls_rs;
}
sub get_contract_zonesfees_rs {
    my $self = shift;
    my %params = @_;
    (my ($c,$provider_id,$client_id,$stime,$etime)) = @params{qw/c provider_id client_id stime etime/};
    my $source_account_id_condition;
    if(!$client_id){
        $source_account_id_condition = { 'in' => $self->getInvoiceProviderClients(%params)->search_rs({},{
            'select' => 'me.id',
        })->as_query() };
    }else{
        $source_account_id_condition = $client_id;
    }
    
    # SELECT 'out' as direction, SUM(c.source_customer_cost) AS cost, b.zone,
                         # COUNT(*) AS number, SUM(c.duration) AS duration
                    # FROM accounting.cdr c
                    # LEFT JOIN billing.voip_subscribers v ON c.source_user_id = v.uuid
                    # LEFT JOIN billing.billing_zones_history b ON b.id = c.source_customer_billing_zone_id
                   # WHERE v.contract_id = ?
                     # AND c.call_status = 'ok'
                         # $start_time $end_time
                   # GROUP BY b.zone 

    my $zonecalls_rs = $self->schema->resultset('cdr')->search( {
#        source_user_id => { 'in' => [ map {$_->uuid} @{$contract->{subscriber}} ] },
        call_status       => 'ok',
        source_user_id    => { '!=' => '0' },
        #source_account_id => $source_account_id_condition,
        
        # start_time        => 
            # [ -and =>
                # { '>=' => $stime->epoch},
                # { '<=' => $etime->epoch},
            # ],

    },{
        '+select'   => [ 
            { sum         => 'me.source_customer_cost', -as => 'cost', }, 
            { sum         => 'me.source_customer_free_time', -as => 'free_time', } , 
            { sum         => 'me.duration', -as => 'duration', } , 
            { count       => '*', -as => 'number', } ,
            'source_customer_billing_zones_history.zone', 
            'source_customer_billing_zones_history.detail', 
        ],
        '+as' => [qw/cost free_time duration number zone zone_detail/],
        #alias => 
        join        => 'source_customer_billing_zones_history',
        group_by    => 'source_customer_billing_zones_history.zone',
        #order_by    => 'source_customer_billing_zones_history.zone',
    } );    
    
    return $zonecalls_rs;
}

1;