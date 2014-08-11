package NGCP::Panel::Utils::Invoice;

use Geography::Countries qw/country/;
use Sipwise::Base;
use HTML::Entities;

sub get_invoice_amounts{
    my(%params) = @_;
    my($customer_contract,$billing_profile,$contract_balance) = @params{qw/customer_contract billing_profile contract_balance/};
    my $invoice = {};
    $contract_balance->{cash_balance_interval} //= 0;
    $billing_profile->{interval_charge} //= 0;
    $customer_contract->{vat_rate} //= 0;
    #use Data::Dumper;
    #print Dumper [$contract_balance,$billing_profile]; 
    $invoice->{amount_net} = $contract_balance->{cash_balance_interval} / 100 + $billing_profile->{interval_charge};
    $invoice->{amount_vat} = 
        $customer_contract->{add_vat} 
        ?
            $invoice->{amount_net} * ($customer_contract->{vat_rate}/100) 
            : 0,
    $invoice->{amount_total} =  $invoice->{amount_net} + $invoice->{amount_vat};
    return $invoice;
}
sub get_invoice_serial{
    my($c,$params) = @_;
    my($invoice) = @$params{qw/invoice/};
    return sprintf("INV%04d%02d%07d", $invoice->{period_start}->year,  $invoice->{period_start}->month, $invoice->{id});
}
sub prepare_contact_data{
    my($contact) = @_;
    $contact->{country} = country($contact->{country} || 0);
    foreach(keys %$contact){
        $contact->{$_} = encode_entities($contact->{$_}, '<>&"');
    }
    #passed by reference
    #return $contact;
}
1;
# vim: set tabstop=4 expandtab:
