package NGCP::Panel::Controller::API::InvoiceTemplates;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::InvoiceTemplates/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines invoice templates used to generate customer invoices. Only returns meta data at this point.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for invoice templates belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for invoice templates with a specific name',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.name' => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
