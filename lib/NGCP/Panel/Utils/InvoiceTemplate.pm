package NGCP::Panel::Utils::InvoiceTemplate;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;

sub getDefault{
    my %params = @_;

    my $c = $params{c};
    #in future kay be we will store it in Db, but now it is convenient to edit template as file
    return ${$params{invoicetemplate}} = $c->view('SVG')->getTemplateContent($c, 'customer/calls_svg.tt');
}

1;