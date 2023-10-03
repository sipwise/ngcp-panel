package NGCP::Panel::Controller::API::ResellerPhonebookEntries;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ResellerPhonebookEntries/;

use NGCP::Panel::Utils::Phonebook;

__PACKAGE__->set_config({
    POST => {
        'ContentType'         => ['text/csv', 'application/json'],
        #request_params are taken as native hash and doesn't require any json validation or decoding
        'ResourceContentType' => 'native',
    },
    allowed_roles   => [qw/admin reseller/],
    allowed_ngcp_types => [qw/carrier sppro/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines reseller phonebook entries. You can POST numbers individually one-by-one using json. For bulk uploads specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true"';
}

sub order_by_cols {
    return {name => 'me.name', number => 'me.number'};
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for Phonebook entries belonging to a specific reseller',
            query_type => 'string_eq',
        },
        {
            param => 'number',
            description => 'Filter for Phonebook numbers with a specific number (wildcards possible)',
            query_type => 'string_like',
        },
        {
            param => 'name',
            description => 'Filter for Phonebook numbers with a specific name (wildcards possible)',
            query_type => 'string_like',
        },
    ];
}

sub check_create_csv :Private {
    my ($self, $c) = @_;
    return 'reseller_phonebookentries_list.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    my $rs = $self->item_rs($c);
    NGCP::Panel::Utils::Phonebook::download_csv($c, $rs, 'reseller');
}

sub process_data :Private {
    my ($self, %params) = @_;
    my ($c,$data_ref,$resource,$form,$process_extras) = @params{qw/c data resource form process_extra/}; 
    my $rs = $self->_item_rs($c);
    my $params = $c->req->params;
    my $reseller_id = $params->{reseller_id} // '';

    my ($entries, $fails, $text) =
        NGCP::Panel::Utils::Phonebook::upload_csv($c, $rs, 'reseller', 
            $reseller_id, $params->{purge_existing}, $data_ref);
    $c->log->info( $$text );
}

1;

# vim: set tabstop=4 expandtab:
