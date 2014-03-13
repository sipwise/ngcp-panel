package NGCP::Panel::Model::DB::InvoiceTemplate;
use base NGCP::Panel::Model::DB::Base;

sub getCustomerInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_sourcestate,$tt_type) = @params{qw/contract_id tt_sourcestate tt_type/};

    my $result = '';
    my $tt_id = '';
    
    #my $tt_record = $self->resultset('invoice_template')->search({
    my $tt_record = $self->schema->resultset('invoice_template')->search({
        reseller_id => $contract_id,
        is_active   => 1,
        type        => $tt_type
    })->first;
    #here may be base64 decoding
    
    #here we will rely on form checking and defaults
    #if('saved' eq $tt_sourcestate){
    if( $tt_record ){
        $result = $tt_record->get_column( 'base64_'.$tt_sourcestate );
        $tt_id = $tt_record->get_column( 'id' );
    }
    if( $result && exists $params{result} ){
        ${$params{result}} = $result;
    }
    return ( $tt_id,\$result, $tt_record );#sgorila hata, gori i saray
}

sub storeCustomerInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_sourcestate,$tt_type, $tt_string, $tt_id) = @params{qw/contract_id tt_sourcestate tt_type tt_string_sanitized tt_id/};

    #my $tt_record = $self->resultset('invoice_template')->search({
    $self->schema->txn_do(sub {
#reseller_id and is_active aren't unique key, because is_active can kepp some 0 values for one reseller, we shouldn't keep active and inactive in one table
#        $self->schema->resultset('invoice_template')->update_or_create({
#            reseller_id => $contract_id,
#            type        => $tt_type,
#            is_active   => 1,
#            'base64_'.$tt_sourcestate => $$tt_string,
#        });

        my $tt_record = $self->schema->resultset('invoice_template')->search({
            reseller_id => $contract_id,
            type        => $tt_type,
            is_active   => 1,
        })->first;
        #here may be base64 decoding

#        $self->schema->resultset('ivoice_template')->search({
#            reseller_id => $contract_id,
#            type        => $tt_type,
#        })->update_all({
#            is_active   => 0,
#        });
        
        if( !$tt_record ){
            $self->schema->resultset('invoice_template')->create({
                reseller_id => $contract_id,
                type        => $tt_type,
                is_active   => 1,
                'base64_'.$tt_sourcestate => $$tt_string,
            });
        }else{
            $self->schema->resultset('invoice_template')->update({
                reseller_id => $contract_id,
                type        => $tt_type,
                is_active   => 1,
                'base64_'.$tt_sourcestate => $$tt_string,
                id          => $tt_record->get_column( 'id' ),
            },
            {   key => 'id' });
        }
    });
}

1;