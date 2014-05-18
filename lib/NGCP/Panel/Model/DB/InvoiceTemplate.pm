package NGCP::Panel::Model::DB::InvoiceTemplate;
use base NGCP::Panel::Model::DB::Base;

#use irka;
use Data::Dumper;

sub getDefaultConditions{
    my $self = shift;
    my ($params) = @_;
    my ($provider_id,$tt_sourcestate,$tt_type,$tt_id) = @$params{qw/provider_id tt_sourcestate tt_type tt_id/};
    my $conditions = {};
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

    my $result = '';
    
    #it is hard to express my disappointment by DBIx implementation. Where pure SQL is easy to automate, flexible and powerful, with DBIx you can't even get DB as aliases, only additional accessors, which aren't an option. What a poor "wonabe hibernate" idea and implementation.
    my $tt_record = $self->schema->resultset('invoice_templates')->search( 
        { id => $tt_id }, {
        }
    )->first;
    #here may be base64 decoding
    
    #here we will rely on form checking and defaults
    #if('saved' eq $tt_sourcestate){
    if( $tt_record ){
        $tt_sourcestate and $result = $tt_record->get_column( 'base64_'.$tt_sourcestate );
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

sub getContractInfo{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id) = @params{qw/contract_id/};
    return  $self->schema->resultset('contracts')->search({
        id => $contract_id,
    })->first;
}
sub getContactInfo{
    my $self = shift;
    my (%params) = @_;
    my ($contact_id) = @params{qw/contact_id/};
    return  $self->schema->resultset('contacts')->search({
        id => $contact_id,
    })->first;
}
sub getBillingProfile{
    my $self = shift;
    my ($params) = @_;
    my ($client_contract_id, $stime, $etime) = @$params{qw/client_contract_id stime etime/};
    #select distinct billing_profiles.* 
    #from billing_mappings
    #inner join billing_profiles on billing_mappings.billing_profile_id=billing_profiles.id
    #inner join contracts on contracts.id=billing_mappings.contract_id
    #inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
    #where 
    #    contracts.status != "terminated"
    #    and contracts.contact_id=?
    #    and (billing_mappings.start_date <= ? OR billing_mappings.start_date IS NULL)
    #    and (billing_mappings.end_date >= ? OR billing_mappings.end_date IS NULL)
    return  $self->schema->resultset('billing_profiles')->search({
        'contract.id' => $client_contract_id,
        #'contract.status' => { '!=' => 'terminated' },
        'product.class' => { '-in' => [qw/sipaccount pbxaccount/] },
        'billing_mappings.start_date' => [
            { '<=' => $etime->epoch },
            { -is  => undef },
        ],
        'billing_mappings.end_date' => [
            { '>=' => $stime->epoch },
            { -is  => undef },
        ],
    },{
        'join' => [ { 'billing_mappings' => [ 'product', 'contract' ] } ],
    })->first;
}
sub getContractBalance{
    my $self = shift;
    my ($params) = @_;
    my ($client_contract_id, $stime, $etime) = @$params{qw/client_contract_id stime etime/};
    #select distinct billing_profiles.* 
    #from billing_mappings
    #inner join billing_profiles on billing_mappings.billing_profile_id=billing_profiles.id
    #inner join contracts on contracts.id=billing_mappings.contract_id
    #inner join products on billing_mappings.product_id=products.id and products.class in("sipaccount","pbxaccount")
    #where 
    #    contracts.status != "terminated"
    #    and contracts.contact_id=?
    #    and (billing_mappings.start_date <= ? OR billing_mappings.start_date IS NULL)
    #    and (billing_mappings.end_date >= ? OR billing_mappings.end_date IS NULL)
    return  $self->schema->resultset('contract_balances')->search({
        'contract_id' => $client_contract_id,
        #'contract.status' => { '!=' => 'terminated' },
        '-and'  =>  [
            'start' => [
                { '='  => $stime->datetime },
                { '-is' => undef },
            ],
            'end' => [
                { '='  => $etime->datetime },
                { '-is' => undef },
            ],
        ],
    },undef)->first;
}

sub getProviderInvoiceList{
    my $self = shift;
    my (%params) = @_;
    my ($provider_reseller_id,$stime,$etime) = @params{qw/provider_id stime etime/};
    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime ||= $stime->clone->add( months => 1);
    $self->schema->resultset('invoices')->search({
        '-and'  =>  
            [ 
                'contact.reseller_id' => $provider_reseller_id, #$client_contract_id - contract of the client
            ],
    },{
        'select'   => [ 'contract_balances.invoice_id','contract_balances.start','contract_balances.end','contract_balances.cash_balance','contract_balances.free_time_balance','reseller.id','reseller.name','contact.id',],
        'as'       => [ 'invoice_id','contract_balance_start','contract_balance_end','cash_balance','free_time_balance', 'reseller_id', 'reseller_name','client_contact_id' ],
        'prefetch' => [ {'contract_balances' => { 'contract' => { 'contact' => 'reseller' } } } ],
        #'collapse' => 1,
        'order_by' => [ { '-desc' => 'contract_balances.start' },{ '-asc' => 'contract_balances.end' }, ],
        'alias'    => 'me',
    });
}
sub getProviderInvoiceListAjax{
    my $self = shift;
    my (%params) = @_;
    my ($provider_reseller_id,$client_contact_id,$stime,$etime) = @params{qw/provider_id client_contact_id stime etime/};
    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime ||= $stime->clone->add( months => 1);
    $self->schema->resultset('invoices')->search({
        '-and'  =>  
            [ 
                'contact.reseller_id' => $provider_reseller_id, #$client_contract_id - contract of the client
                $client_contact_id ? ('contact.id' => $client_contact_id) : (), #$client_contract_id - contract of the client
            ],
    },{
        #'select'   => [ 'contract_balances.invoice_id','contract_balances.start','contract_balances.end','contract_balances.cash_balance','contract_balances.free_time_balance','reseller.id','reseller.name','contact.id',],
        #'as'       => [ 'invoice_id','contract_balance_start','contract_balance_end','cash_balance','free_time_balance', 'reseller_id', 'reseller_name','client_contact_id' ],
        #'prefetch' => [ {'contract_balances' => { 'contract' => { 'contact' => 'reseller' } } } ],
        ##'collapse' => 1,
        #'order_by' => [ { '-desc' => 'contract_balances.start' },{ '-asc' => 'contract_balances.end' }, ],
        #'alias'    => 'me',
    });
}
sub createInvoice{
    my $self = shift;
    my (%params) = @_;
    my ($contract_balance,$data,$stime,$etime) = @params{qw/contract_balance data stime etime/};
    
    #    my($contract_id, $stime, $etime) = @_;
    ##my $invoice_serial = $dbh->selectrow_array('select max(invoices.serial) from invoices inner join contract_balances on invoices.id=contract_balances.invoice_id where contract_balances.contract_id=?',undef,$contract_id );    
    #my $invoice_serial = $dbh->selectrow_array('select max(invoices.serial) from invoices'); 
    #$invoice_serial += 1;
    #$dbh->do('insert into invoices(year,month,serial)values(?,?,?)', undef, $stime->year, $stime->month,$invoice_serial );
    #my $invoice_id = $dbh->last_insert_id(undef,'billing','invoices','id');
    #$dbh->do('update contract_balances set invoice_id = ? where contract_id=? and start=? and end=?', undef, $invoice_id,$contract_id, $stime->datetime, $etime->datetime );
    #return $dbh->selectrow_hashref('select * from invoices where id=?',undef, $invoice_id);    
    my $invoice;
    
    if( $contract_balance->get_column('invoice_id')){
        $invoice = $self->schema->resultset('invoices')->search({
            id   =>  $contract_balance->get_column('invoice_id'),
        })->first;
    }else{
    
        my $invoice_serial = $self->schema->resultset('invoices')->search(undef, {
            'select'  => { 'max' => 'me.serial', '-as' => 'serial_max'},
        })->first->get_column('serial_max');
        $invoice_serial +=1;

        my $invoice_record = $self->schema->resultset('invoices')->create({
            year   => $stime->year,
            month  => $stime->month,
            serial => $invoice_serial,
            data   => $data,
        });
        if($invoice_record){
            $self->schema->resultset('contract_balances')->search({
                id   => $contract_balance->get_column('id'),
            })->update({
                invoice_id => $invoice_record->id()
            });
            $invoice = $self->schema->resultset('invoices')->search({
                id   =>  $invoice_record->id(),
            })->first;
        }
    }
    return $invoice;
}
sub storeInvoiceData{
    my $self = shift;
    my (%params) = @_;
    my ($invoice,$data_ref) = @params{qw/invoice data/};
    $self->schema->resultset('invoices')->search({
        id   => $invoice->get_column('id'),
    })->update({
        data => $$data_ref
    });    
}
sub getInvoice{
    my $self = shift;
    my (%params) = @_;
    my ($invoice_id) = @params{qw/invoice_id/};
    return $self->schema->resultset('invoices')->search({
        'id'  => $invoice_id,
    }, undef )->first;
}
sub deleteInvoice{
    my $self = shift;
    my (%params) = @_;
    my ($invoice_id) = @params{qw/invoice_id/};
    
    $self->schema->resultset('invoices')->search({
        'id'  => $invoice_id,
    }, undef )->delete;
    
    $self->schema->resultset('contract_balances')->search({
        'invoice_id'  => $invoice_id,
    }, undef )->update({
        'invoice_id'  => undef,    
    });
}
sub getInvoiceProviderClients{
    my $self = shift;
    my (%params) = @_;
    my ($provider_contact_id,$stime,$etime) = @params{qw/provider_id stime etime/};
    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime ||= $stime->clone->add( months => 1);
    $self->schema->resultset('contacts')->search_rs({
        '-and'  =>  
            [ 
                'me.reseller_id' => $provider_contact_id, #$client_contract_id - contract of the client
            ],
        '-exists' => $self->schema->resultset('billing_mappings')->search({
            #here rely on join generated by datatables 
            'contract.id' => \' = contracts.id',
            'product.class' => [ "sipaccount", "pbxaccount" ],
            #'-and'          => [
            #        'start_date'    => [ -or =>
            #            { '<=' => $etime->epoch },
            #            { -is  => undef },
            #        ],
            #        'end_date' => [ -or =>
            #            { '>=' => $stime->epoch },
            #            { -is  => undef },
            #        ],
            #    ]
            },{
                alias => 'billing_mappings_top',
                join => ['product','contract'],
        })->as_query
    });
}
sub call_owner_condition{
    my $self = shift;
    my ($params) = @_;
   (my($c,$provider_id,$client_contact_id,$client_contract_id)) = @$params{qw/c provider_id client_contact_id client_contract_id/};
    my %source_account_id_condition;
    if($client_contract_id){
        %source_account_id_condition = ( 'source_account_id' => $client_contract_id );
    }elsif($client_contact_id){
        %source_account_id_condition = ( 
            'source_account.contact_id' => $client_contact_id,
            'contact.reseller_id' => { '!=' => undef },
        );
    }elsif($provider_id){
        %source_account_id_condition = (
            'contact.reseller_id' => $client_contact_id,
        );
    }
    return \%source_account_id_condition;
}
sub get_contract_calls_rs{
    my $self = shift;
    my %params = @_;
    (my($c,$provider_id,$client_contact_id,$client_contract_id,$stime,$etime)) = @params{qw/c provider_id client_contact_id client_contract_id stime etime/};

    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime ||= $stime->clone->add( months => 1 );

    my %source_account_id_condition = %{$self->call_owner_condition(\%params)};

    my $calls_rs = $self->schema->resultset('cdr')->search( {
#        source_user_id => { 'in' => [ map {$_->uuid} @{$contract->{subscriber}} ] },
        'call_status'       => 'ok',
        'source_user_id'    => { '!=' => '0' },
        'contact.reseller_id' => { '!=' => undef },
        start_time        => 
            [ -and =>
                { '>=' => $stime->epoch},
                { '<=' => $etime->epoch},
            ],
        %source_account_id_condition
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
        ],
        'order_by'    => { '-desc' => 'start_time'},
    } );    
 
    return $calls_rs;
}
sub get_contract_zonesfees_rs {
    my $self = shift;
    my %params = @_;
    (my($c,$provider_id,$client_contact_id,$client_contract_id,$stime,$etime)) = @params{qw/c provider_id client_contact_id client_contract_id stime etime/};

    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime ||= $stime->clone->add( months => 1 );

    my %source_account_id_condition = %{$self->call_owner_condition(\%params)};
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
        'call_status'       => 'ok',
        'source_user_id'    => { '!=' => '0' },
        start_time        => 
            [ -and =>
                { '>=' => $stime->epoch},
                { '<=' => $etime->epoch},
            ],
        %source_account_id_condition
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
        order_by    => 'source_customer_billing_zones_history.zone',
    } );    
    
    return $zonecalls_rs;
}

sub checkResellerClientContract{
    my($self,$in) = @_;
    my $res = 0;
    
    if($in->{client_contract_id} && $in->{provider_id}){
        if(my $contract = $self->schema->resultset('contracts')->search({
            'contact.reseller_id' => $in->{provider_id},
            'me.id' => $in->{client_contract_id},
        },{
            'join' => 'contact',
        })->first){
            $res = $contract->get_column('id');
        }
    }
    return $res;
}

sub checkResellerClientContact{
    my($self,$in) = @_;
    my $res = 0;
    
    if($in->{client_contact_id} && $in->{provider_id}){
        if(my $contact = $self->schema->resultset('contacts')->search({
            'reseller_id' => $in->{provider_id},
            'id' => $in->{client_contact_id},
        })->first){
            $res = $contact->get_column('id');
        }
    }
    return $res;
}

sub checkResellerInvoice{
    my($self,$in) = @_;
    my $res = 0;
    
    if($in->{invoice_id} && $in->{provider_id}){
        if(my $invoice = $self->schema->resultset('invoices')->search({
            'contact.reseller_id' => $in->{provider_id},
            'id' => $in->{client_contact_id},
        },{
            'join' => { 'contract_balances' => { 'contract' => 'contact' }},
        })->first){
            $res = $invoice->get_column('id');
        }
    }
    return $res;
}

sub checkResellerInvoiceTemplate{
    my($self,$in) = @_;
    my $res = 0;
    #no warnings 'uninitialized';
    #$in->{c}->log->debug("checkResellerInvoiceTemplate: tt_id=".$in->{tt_id}.";provider_id=".$in->{provider_id}.";");

    if($in->{tt_id} && $in->{provider_id}){
        #$in->{c}->log->debug("checkResellerInvoiceTemplate: tt_id=".$in->{tt_id}.";provider_id=".$in->{provider_id}.";");
        if(my $tt = $self->schema->resultset('invoice_templates')->search({
            'reseller_id' => $in->{provider_id},
            'id' => $in->{tt_id},
        })->first){
            $res = $tt->get_column('id');
        }
    }
    #$in->{c}->log->debug("checkResellerInvoiceTemplate: res=".$res.";");
    return $res;
}

1;