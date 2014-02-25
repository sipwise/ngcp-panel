package NGCP::Panel::Utils::InvoiceTemplate;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;
#use NGCP::Panel::Utils::DateTime;

sub getDefault{
    my %params = @_;

    my $c = $params{c};
    #in future kay be we will store it in Db, but now it is convenient to edit template as file
    return ${$params{invoicetemplate}} = $c->view('SVG')->getTemplateContent($c, 'customer/calls_svg.tt');
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