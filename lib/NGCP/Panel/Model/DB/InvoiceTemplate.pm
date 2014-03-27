package NGCP::Panel::Model::DB::InvoiceTemplate;
use base NGCP::Panel::Model::DB::Base;

use irka;
use Data::Dumper;

sub getDefaultConditions{
    my $self = shift;
    my ($params) = @_;
    irka::loglong(Dumper($params));
    my ($contract_id,$tt_sourcestate,$tt_type,$tt_id) = @$params{qw/contract_id tt_sourcestate tt_type tt_id/};
    my $conditions = {};
    irka::loglong("getDefaultConditions: tt_id=$tt_id;\n");
    #my $tt_record = $self->resultset('invoice_template')->search({
    if($tt_id){
        $conditions = { id => $tt_id };
    }else{
        $conditions = {
            reseller_id => $contract_id,
            type        => $tt_type,
            is_active   => 1,
        };
    }
    return $conditions;
}
sub getCustomerInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_sourcestate,$tt_type,$tt_id) = @params{qw/contract_id tt_sourcestate tt_type tt_id/};

    irka::loglong("getCustomerInvoiceTemplate: tt_id=$tt_id;\n");
    irka::loglong(Dumper(\%params));
    my $result = '';
    
    my $conditions = $self->getDefaultConditions(\%params);
    #my $tt_record = $self->resultset('invoice_template')->search({
    my $tt_record = $self->schema->resultset('invoice_template')->search($conditions)->first;
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
    return ( $tt_id, \$result, $tt_record );#tt_record - sgorila hata, gori i saray
}

sub storeCustomerInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id, $tt_sourcestate, $tt_type,$tt_string,$tt_id,$is_active,$name) = @params{qw/contract_id tt_sourcestate tt_type tt_string_sanitized tt_id is_active name/};

    #my $tt_record = $self->resultset('invoice_template')->search({
    $self->schema->txn_do(sub {
#reseller_id and is_active aren't unique key, because is_active can kepp some 0 values for one reseller, we shouldn't keep active and inactive in one table
#        $self->schema->resultset('invoice_template')->update_or_create({
#            reseller_id => $contract_id,
#            type        => $tt_type,
#            is_active   => 1,
#            'base64_'.$tt_sourcestate => $$tt_string,
#        });


        #here may be base64 decoding

#        $self->schema->resultset('ivoice_template')->search({
#            reseller_id => $contract_id,
#            type        => $tt_type,
#        })->update_all({
#            is_active   => 0,
#        });
        
        if( !$tt_id ){
            $self->schema->resultset('invoice_template')->create({
                reseller_id => $contract_id,
                type        => $tt_type,
                is_active   => 1,
                name        => $name,
                'base64_'.$tt_sourcestate => $$tt_string,
            });
        }else{
            my $conditions = $self->getDefaultConditions(\%params);
            my $tt_record = $self->schema->resultset('invoice_template')->search($conditions);
            $tt_record->update({
                is_active   => $is_active,
                name        => $name,
                'base64_'.$tt_sourcestate => $$tt_string,
            });
        }
    });
}
sub getCustomerInvoiceTemplateList{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_sourcestate,$tt_type, $tt_string, $tt_id) = @params{qw/contract_id tt_sourcestate tt_type tt_string_sanitized tt_id/};
    
    return [ $self->schema->resultset('invoice_template')->search({
        reseller_id => $contract_id,
    })->all ];
}
sub deleteCustomerInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_id) = @params{qw/contract_id tt_id/};
    return $self->schema->resultset('invoice_template')->search({
        reseller_id => $contract_id,
        id => $tt_id,
    })->delete_all;
}
sub checkCustomerInvoiceTemplateContract{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_id) = @params{qw/contract_id tt_id/};
    my $tt_record = $self->schema->resultset('invoice_template')->search({
        reseller_id => $contract_id,
        id => $tt_id,
    });
    if($tt_record->get_column('id')){
        return 1;
    }
    return 0;
}
1;