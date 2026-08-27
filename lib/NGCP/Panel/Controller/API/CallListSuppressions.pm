package NGCP::Panel::Controller::API::CallListSuppressions;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallListSuppressions/;

use NGCP::Panel::Utils::CallList;
use NGCP::Panel::Utils::MySQL;

__PACKAGE__->set_config({
    POST => {
        'ContentType'         => ['text/csv', 'application/json'],
        #request_params are taken as native hash and doesn't require any json validation or decoding
        'ResourceContentType' => 'native',
    },
    allowed_roles => [qw/admin/],
});

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines global call list suppressions, which hide or obfuscate matching numbers in the <a href="#calllists">Call Lists</a> of subscriber and subscriber admin users. '.
           'A suppression applies to the subscribers of the given "domain", or to the subscribers of any domain if "domain" is empty. '.
           'In "filter" mode matching calls do not appear at all, in "obfuscate" mode the number is replaced by the given "label", and in "disabled" mode the suppression is not applied. '.
           'Admin and reseller users always see the unsuppressed call lists. The combination of "domain", "direction" and "pattern" must be unique. '.
           'You can POST suppressions individually one-by-one using json. For bulk uploads specify the Content-Type as "text/csv" and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true". '.
           'The CSV columns are "domain,direction,pattern,mode,label" without a header row. To download all the suppressions in CSV format, GET the collection with an "Accept: text/csv" header.';
}

sub order_by_cols {
    return {
        id => 'me.id',
        domain => 'me.domain',
        direction => 'me.direction',
        pattern => 'me.pattern',
        mode => 'me.mode',
        label => 'me.label',
    };
}

sub query_params {
    return [
        {
            param => 'domain',
            description => 'Filter for call list suppressions of a specific domain. Use an empty value to filter for the suppressions applying to any domain.',
            query_type => 'wildcard',
        },
        {
            param => 'direction',
            description => 'Filter for call list suppressions with a specific direction ("outgoing" or "incoming")',
            query_type => 'string_eq',
        },
        {
            param => 'mode',
            description => 'Filter for call list suppressions with a specific mode ("filter", "obfuscate" or "disabled")',
            query_type => 'string_eq',
        },
        {
            param => 'pattern',
            description => 'Filter for call list suppressions with a specific pattern',
            query_type => 'wildcard',
        },
        {
            param => 'label',
            description => 'Filter for call list suppressions with a specific label',
            query_type => 'wildcard',
        },
    ];
}

sub check_create_csv :Private {
    my ($self, $c) = @_;
    return 'call_list_suppressions.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    #_item_rs and not item_rs: like the "Download CSV" button of the web
    #interface, the whole table is exported and the query parameters are ignored
    NGCP::Panel::Utils::CallList::create_suppressions_csv(
        c  => $c,
        rs => $self->_item_rs($c),
    );
}

sub process_data :Private {
    my ($self, %params) = @_;
    my ($c,$data_ref,$resource,$form,$process_extras) = @params{qw/c data resource form process_extras/};

    my $schema = $c->model('DB');
    my $purge_existing = $c->req->params->{purge_existing} // '';

    if ($purge_existing eq 'true' || $purge_existing eq '1') {
        #the transaction guard is already opened by NGCP::Panel::Role::Entities::post,
        #so do_transaction => 0, the same way the web interface does it
        NGCP::Panel::Utils::MySQL::truncate_table(
            c              => $c,
            schema         => $schema,
            do_transaction => 0,
            table          => 'billing.call_list_suppressions',
        );
    }

    #upload_suppressions_csv returns two values only, unlike the upload_csv of
    #the other resources, which also return the list of the accepted records
    my ($fails, $text_success) = NGCP::Panel::Utils::CallList::upload_suppressions_csv(
        c      => $c,
        data   => $data_ref,
        schema => $schema,
    );
    $c->log->info($$text_success);

    return;
}

1;

# vim: set tabstop=4 expandtab:
