package NGCP::Panel::Controller::API::Customers;
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
    return 'Defines a billing container for end customers. Customers usually have one or more <a href="#subscribers">Subscribers</a>. A <a href="#billingprofiles">Billing Profile</a> is assigned to a customer, and it has <a href="#contractbalances">Contract Balances</a> indicating the saldo of the customer for current and past billing intervals. Customer can be one of the "sipaccount" or "pbxaccount" type. Type should be specified as "type" parameter.';
};
sub documentation_sample {
    return
        {
           "billing_profile_id" => 4,
           "type" => "sipaccount",
           "contact_id" => 4,
           "status" => "test",
        }
    ;
}

sub query_params {
    my $params = [
        {
            param => 'status',
            description => 'Filter for customers with a specific status (comma-separated list of statuses to include possible)',
            query => {
                first => sub {
                    my $q = shift;
                    my @l = split /,/, $q;
                    { 'me.status' => { -in => \@l }};
                },
                second => sub { },
            },
        },
        {
            param => 'not_status',
            description => 'Filter for customers not having a specific status (comma-separated list of statuses to exclude possible)',
            query => {
                first => sub {
                    my $q = shift;
                    my @l = split /,/, $q;
                    { 'me.status' => { -not_in => \@l }};
                },
                second => sub { },
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for customers belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    { join => 'contact' };
                },
            },
        },
        {
            param => 'external_id',
            description => 'Filter for customer with specific external_id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.external_id' => { like => $q } };
                },
                second => sub { },
            },
        },
        {
            param => 'contact_id',
            description => 'Filter for customers belonging to a specific contact',
            query => {
                first => sub {
                    my $q = shift;
                    { contact_id => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'package_id',
            description => 'Filter for customers with specific profile package id',
            query => {
                first => sub {
                    my $q = shift;
                },
                second => sub { },
            },
        },
    ];
    foreach my $field (qw/create_timestamp activate_timestamp modify_timestamp terminate_timestamp/){
        push @$params, {
            param => $field.'_gt',
            description => 'Filter for customers with '.$field.' greater then specified value',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.'.$field => { '>=' => $q } };
                },
                second => sub { },
            },
        },
        {
            param => $field.'_lt',
            description => 'Filter for customers with '.$field.' less then specified value',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.'.$field => { '<=' => $q } };
                },
                second => sub { },
            },
        };
    }
    return $params;
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Customers/;

sub resource_name{
    return 'customers';
}

sub dispatch_path{
    return '/api/customers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $customers_rs = $self->item_rs($c,$now);
        (my $total_count, $customers_rs, my $customers_rows) = $self->paginate_order_collection($c, $customers_rs);
        my $customers = NGCP::Panel::Utils::Contract::acquire_contract_rowlocks(c => $c,
            rs => $customers_rs,
            contract_id_field => 'id');
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $customer (@$customers) {
            push @embedded, $self->hal_from_customer($c, $customer, $form, $now);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $customer->id),
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
        #$resource->{profile_package_id} = undef unless NGCP::Panel::Utils::ProfilePackages::ENABLE_PROFILE_PACKAGES;

        my $custcontact = $c->model('DB')->resultset('contacts')
            ->search({
                'me.status' => { '!=' => 'terminated' },
            })->find($resource->{contact_id});
        unless($custcontact) {
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

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        $resource->{create_timestamp} = $now;
        $resource->{modify_timestamp} = $now;
        my $customer;

        try {
            $customer = $schema->resultset('contracts')->create($resource);
            $c->log->debug("customer id " . $customer->id . " created");
        } catch($e) {
            $c->log->error("failed to create customer contract: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create customer.");
            last;
        }

        unless($customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The contact_id is not a valid ngcp:customercontacts item, but an ngcp:systemcontacts item");
            last;
        }

        #todo: strange: why do we check this after customer creation?
        my $tmplfields = $self->get_template_fields_spec();
        foreach my $field (keys %$tmplfields){
            next unless $customer->$field();

            my $field_table_rel = $tmplfields->{$field}->[1];
            unless($customer->$field_table_rel()->reseller_id && 
                    $customer->$field_table_rel()->reseller_id == $customer->contact->reseller_id) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "'$field' with value '" . $customer->$field() 
                    . "' does not belong to Reseller '" . $customer->contact->reseller_id 
                    . "' that is assigned to Customer's Contact '$resource->{contact_id}'");
                return;
            }
        }

        try {
            NGCP::Panel::Utils::BillingMappings::append_billing_mappings(c => $c,
                contract => $customer,
                mappings_to_create => $mappings_to_create,
            );
            $customer = $self->customer_by_id($c, $customer->id,$now);
            NGCP::Panel::Utils::ProfilePackages::create_initial_contract_balances(c => $c,
                contract => $customer,
            );
        } catch($e) {
            $c->log->error("failed to create customer contract: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create customer.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_customer = $self->customer_by_id($c, $customer->id);
            return $self->hal_from_customer($c,$_customer,$form, $now); }); #$form

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $customer->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
