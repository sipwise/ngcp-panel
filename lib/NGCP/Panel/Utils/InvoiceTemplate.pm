package NGCP::Panel::Utils::InvoiceTemplate;
use strict;
use warnings;
use Moose;
use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;
#use NGCP::Panel::Utils::DateTime;

sub getDefault{
    my %params = @_;

sub getDefaultInvoiceTemplate{
    my (%in) = @_;
    #in future may be we will store root default in Db too, but now it is convenient to edit template as file
    my $result = $in{c}->view('SVG')->getTemplateContent($in{c}, 'customer/calls_'.$in{type}.'.tt');
    
    #$in{c}->log->debug("result=$result;");
    
    if( $result && exists $in{result} ){
        ${$in{result}} = $result;
    }
    return \$result;
}

sub getCustomerTemplate{
    my %params = @_;

    my $c = $params{c};
    my $contract_id = $params{contract_id} || $c->stash->{contract}->id;
    my $tt_state = $params{tt_state} || 'saved';
    my $result;
    
    my $template_record = $c->model('DB')->resultset('invoice_template')->search({
        reseller_id => $contract_id,
        is_active   => 1,
    })->first;
    #here may be base64 decoding
    if('saved' eq $tt_state){
        $result = \$template_record->get_column('base64_'.$tt_state);
    }
    return $result;
}


1;