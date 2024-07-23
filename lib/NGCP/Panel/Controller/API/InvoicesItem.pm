package NGCP::Panel::Controller::API::InvoicesItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Invoices/;

__PACKAGE__->set_config({
    required_licenses => [qw/invoice/],
    log_response => 0,
    GET => {
        #first element of array is default, if no accept header was received.
        'ReturnContentType' => [ 'application/pdf', 'application/json' ],
    },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    delete $resource->{data};
    return $resource;
}

sub get_item_binary_data{
    my($self, $c, $id, $item) = @_;
    #caller waits for: $data_ref,$mime_type,$filename
    #while we will not strictly check Accepted header, if item can return only one type of the binary data
    return \$item->data, 'application/pdf', 'invoice_'.$item->id.'.pdf',
}

1;

# vim: set tabstop=4 expandtab:
