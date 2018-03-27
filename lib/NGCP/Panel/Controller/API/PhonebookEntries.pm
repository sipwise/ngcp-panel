package NGCP::Panel::Controller::API::PhonebookEntries;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PhonebookEntries/;

__PACKAGE__->set_config({
    POST => {
        'ContentType' => ['text/csv', 'application/json'],
    },
    allowed_roles   => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines Phonebook number entries. You can POST numbers individually one-by-one using json. To bulk-upload numbers, specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true", like "/api/phonebookentries/?purge_existing=true"';
}

sub document_sorting_cols {
    return [qw/name number shared/];
}

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for Phonebook entries belonging to a specific reseeller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'contract_id',
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
            query => {
                first => sub {
                    my $q = shift;
                    { subscriber_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'number',
            description => 'Filter for LNP numbers with a specific number (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.number' => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

sub check_create_csv :Private {
    my ($self, $c) = @_;
    return 'phonebookentries_list.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    NGCP::Panel::Utils::Phonebook::create_csv(
        c => $c,
    );
}

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;
    my $rs = $self->_item_rs($c,undef,$resource);#maybe copy-paste it here?
    return unless $rs;
    my $item = $rs->create($resource);
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
