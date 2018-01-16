package NGCP::Panel::Role::API::Invoices;

use parent qw/NGCP::Panel::Role::API/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use HTTP::Status qw(:constants);

sub item_name{
    return 'invoice';
}

sub resource_name{
    return 'invoices';
}

sub dispatch_path{
    return '/api/invoices/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-invoices';
}

sub config_allowed_roles {
    return [qw/admin reseller/];
}

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('invoices');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'contact.reseller_id' => $c->user->reseller_id 
        },{
            join => { contract => 'contact' },
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return (NGCP::Panel::Form::get("NGCP::Panel::Form::Invoice::InvoiceAPI", $c));
}

sub hal_links {
    my($self, $c, $item, $resource, $form) = @_;
    return [
        Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
    ];
}

1;
# vim: set tabstop=4 expandtab:
