package NGCP::Panel::Controller::API::Contracts;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::BillingMappings qw();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a billing container for peerings and resellers. A <a href="#billingprofiles">Billing Profile</a> is assigned to a contract, and it has <a href="#contractbalances">Contract Balances</a> indicating the saldo of the contract for current and past billing intervals.';
};

sub query_params {
    return [
        {
            param => 'contact_id',
            description => 'Filter for contracts with a specific contact id',
            query => {
                first => sub {
                    my $q = shift;
                    { contact_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'status',
            description => 'Filter for contracts with a specific status (except "terminated")',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.status' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'external_id',
            description => 'Filter for contracts with a specific external id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.external_id' => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'type',
            description => 'Filter for contracts with a specific type',
            query => {
                first => sub {
                    my ($q,$c) = @_;
                    my @product_ids = map { $_->id; } $c->model('DB')->resultset('products')->search_rs({ 'class' => [split(/\s*[,;]\s*/,$q)] })->all;
                    { 'product_id' => { -in => [ @product_ids ] }, };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Contracts/;

sub resource_name{
    return 'contracts';
}

sub dispatch_path{
    return '/api/contracts/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-contracts';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $contracts_rs = $self->item_rs($c,0,$now);
        (my $total_count, $contracts_rs, my $contracts_rows) = $self->paginate_order_collection($c, $contracts_rs);
        my $contracts = NGCP::Panel::Utils::Contract::acquire_contract_rowlocks(c => $c,
            rs => $contracts_rs,
            contract_id_field => 'id');
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $contract (@$contracts) {
            #NGCP::Panel::Utils::ProfilePackages::get_contract_balance
            push @embedded, $self->hal_from_contract($c, $contract, $form, $now);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $contract->id),
            );
        }
        $self->delay_commit($c,$guard); #potential db write ops in hal_from
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $response = HTTP::Response->new(HTTP_OK, undef,
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        $resource->{contact_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $syscontact = $schema->resultset('contacts')
            ->search({
                'me.status' => { '!=' => 'terminated' },
            })->find($resource->{contact_id});
        unless($syscontact) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'contact_id'");
            last;
        }

        my $mappings_to_create = [];
        last unless NGCP::Panel::Utils::BillingMappings::prepare_billing_mappings(
            c => $c,
            resource => $resource,
            old_resource => undef,
            mappings_to_create => $mappings_to_create,
            err_code => sub {
                my ($err) = @_;
                #$c->log->error($err);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
            });

        my $product_class = delete $resource->{type};
        my $product = $schema->resultset('products')->search_rs({ class => $product_class })->first;
        unless($product) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'type'.");
            last;
        }
        $resource->{product_id} = $product->id;
        if (
            NGCP::Panel::Utils::Contract::is_peering_reseller_product( c => $c, product => $product )
            &&
            ( my $prepaid_billing_profile_exist = NGCP::Panel::Utils::BillingMappings::check_prepaid_profiles_exist(
                c => $c,
                mappings_to_create => $mappings_to_create) )
        ) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering/reseller contract can't be connected to the prepaid billing profile $prepaid_billing_profile_exist.");
            return;
        }

        if (NGCP::Panel::Utils::Contract::is_peering_product(
            c => $c, product => $product) && defined $resource->{max_subscribers}) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering contract should not have 'max_subscribers' defined.");
            return;
        }

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        $resource->{create_timestamp} = $now;
        $resource->{modify_timestamp} = $now;
        my $contract;

        try {
            $contract = $schema->resultset('contracts')->create($resource);
        } catch($e) {
            $c->log->error("failed to create contract: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create contract.");
            last;
        }

        if($contract->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The contact_id is not a valid ngcp:systemcontacts item, but an ngcp:customercontacts item");
            last;
        }

        try {
            NGCP::Panel::Utils::BillingMappings::append_billing_mappings(c => $c,
                contract => $contract,
                mappings_to_create => $mappings_to_create,
            );

            $contract = $self->contract_by_id($c, $contract->id,1,$now);
            NGCP::Panel::Utils::ProfilePackages::create_initial_contract_balances(c => $c,
                contract => $contract,
            );
        } catch($e) {
            $c->log->error("failed to create contract: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create contract.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_contract = $self->contract_by_id($c, $contract->id, 1);
            return $self->hal_from_contract($c,$_contract,$form,$now); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $contract->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
