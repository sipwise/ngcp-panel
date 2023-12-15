package NGCP::Panel::Controller::API::CustomerPhonebookEntries;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerPhonebookEntries/;

use NGCP::Panel::Utils::Phonebook;

__PACKAGE__->set_config({
    POST => {
        'ContentType'         => ['text/csv', 'application/json'],
        #request_params are taken as native hash and doesn't require any json validation or decoding
        'ResourceContentType' => 'native',
    },
    allowed_roles   => [qw/admin reseller subscriberadmin/],
    allowed_ngcp_types => [qw/carrier sppro/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines customer phonebook entries. You can POST numbers individually one-by-one using json. For bulk uploads specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true"';
}

sub order_by_cols {
    return {name => 'me.name', number => 'me.number'};
}

sub query_params {
    return [
        {
            param => 'customer_id',
            description => 'Filter for Phonebook entries belonging to a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    { contract_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'number',
            description => 'Filter for Phonebook numbers with a specific number',
            query_type => 'wildcard',
        },
        {
            param => 'name',
            description => 'Filter for Phonebook numbers with a specific name',
            query_type => 'wildcard',
        },
    ];
}

sub check_create_csv :Private {
    my ($self, $c) = @_;
    return 'customer_phonebookentries_list.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    my $rs = $self->item_rs($c);
    NGCP::Panel::Utils::Phonebook::download_csv($c, $rs, 'customer');
}

sub process_data :Private {
    my ($self, %params) = @_;
    my ($c,$data_ref,$resource,$form,$process_extras) = @params{qw/c data resource form process_extra/}; 
    my $rs = $self->_item_rs($c);
    my $params = $c->request->params;
    my $customer_id = $params->{'customer_id'} // '';

    my ($entries, $fails, $text) =
        NGCP::Panel::Utils::Phonebook::upload_csv($c, $rs, 'contract',
            $customer_id, $params->{purge_existing}, $data_ref);
    $c->log->info( $$text );
}

1;

# vim: set tabstop=4 expandtab:
