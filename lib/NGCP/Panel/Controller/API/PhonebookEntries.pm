package NGCP::Panel::Controller::API::PhonebookEntries;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PhonebookEntries/;

use NGCP::Panel::Utils::Phonebook;

__PACKAGE__->set_config({
    POST => {
        'ContentType'         => ['text/csv', 'application/json'],
        #request_params are taken as native hash and doesn't require any json validation or decoding
        'ResourceContentType' => 'native',
    },
    allowed_roles   => [qw/admin reseller subscriberadmin subscriber/],
    mandatory_parameters => { 'single' => [qw/reseller_id customer_id subscriber_id/],},
    allowed_ngcp_types => [qw/carrier sppro/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines Phonebook number entries. You can POST numbers individually one-by-one using json. To bulk-upload numbers, specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true", like "/api/phonebookentries/?purge_existing=true"';
}

sub order_by_cols {
    return {name => 'me.name', number => 'me.number'};
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for Phonebook entries belonging to a specific reseeller',
            query_type => 'string_eq',
        },
        {
            param => 'customer_id',
            description => 'Filter for Phonebook entries belonging to a specific contract',
            query => {
                first => sub {
                    my $q = shift;
                    { contract_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'subscriber_id',
            description => 'Filter for Phonebook entries belonging to a specific subscriber',
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
    return 'phonebookentries_list.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    my($owner_obj,$owner_type,$owner_parameter,$owner_id) = $self->check_owner_params($c);
    return unless $owner_obj;
    my $rs = $self->_item_rs($c);
    NGCP::Panel::Utils::Phonebook::download_csv($c, $rs, $owner_type, $owner_id);
}

sub process_data :Private {
    my ($self, %params) = @_;
    my ($c,$data_ref,$resource,$form,$process_extras) = @params{qw/c data resource form process_extra/}; 
    my($owner_obj,$owner_type,$owner_parameter,$owner_id) = $self->check_owner_params($c);
    return unless $owner_obj;
    my $rs = $self->_item_rs($c);

    my ($entries, $fails, $text) =
        NGCP::Panel::Utils::Phonebook::upload_csv($c, $rs, $owner_type, $owner_id,
            $c->req->params->{purge_existing}, $data_ref);
    $c->log->info( $$text );
}

1;

# vim: set tabstop=4 expandtab:
