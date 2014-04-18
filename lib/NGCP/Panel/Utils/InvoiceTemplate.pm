package NGCP::Panel::Utils::InvoiceTemplate;
#it should be part of real model, or subcontroller

use strict;
use warnings;
#use Moose;
use Sipwise::Base;

sub getDefaultInvoiceTemplate{
    my (%in) = @_;
    #in future may be we will store root default in Db too, but now it is convenient to edit template as file
    my $result = $in{c}->view('SVG')->getTemplateContent($in{c}, 'invoice/invoice_template_'.$in{type}.'.tt');
    
    #$in{c}->log->debug("result=$result;");
    
    if( $result && exists $in{result} ){
        ${$in{result}} = $result;
    }
    return \$result;
}

1;