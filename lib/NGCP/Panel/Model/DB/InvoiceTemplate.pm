package NGCP::Panel::Model::DB::InvoiceTemplate;
use base NGCP::Panel::Model::DB::Base;

sub getCustomerInvoiceTemplate{
    my $self = shift;
    my (%params) = @_;
    my ($contract_id,$tt_sourcestate,$tt_type) = @params{qw/contract_id tt_sourcestate/};

    my $result = '';
    
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
        $result = \$tt_record->get_column( 'base64_'.$tt_sourcestate );
    }
    if( $result && exists $params{result} ){
        ${$params{result}} = $result;
    }
    return $result;
}

1;