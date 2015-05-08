package NGCP::Panel::Controller::API::Customers;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use Path::Tiny qw(path);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines a billing container for end customers. Customers usually have one or more <a href="#subscribers">Subscribers</a>. A <a href="#billingprofiles">Billing Profile</a> is assigned to a customer, and it has <a href="#contractbalances">Contract Balances</a> indicating the saldo of the customer for current and past billing intervals. Customer can be one of the "sipaccount" or "pbxaccount" type. Type should be specified as "type" parameter.',
);
class_has 'documentation_sample' => (
    is => 'ro',
    default => sub { 
        {
           "billing_profile_id" => 4,
           "type" => "sipaccount",
           "contact_id" => 4,
           "status" => "test",
        }
    },
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'status',
            description => 'Filter for customers with a specific status (comma-separated list of stati to include possible)',
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
            description => 'Filter for customers not having a specific status (comma-separated list of stati to exclude possible)',
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
                    { 'me.external_id' => $q };
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
    ]},
);

with 'NGCP::Panel::Role::API::Customers';

class_has('resource_name', is => 'ro', default => 'customers');
class_has('dispatch_path', is => 'ro', default => '/api/customers/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-customers');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $customers = $self->item_rs($c);
        (my $total_count, $customers) = $self->paginate_order_collection($c, $customers);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $customer($customers->all) {
            push @embedded, $self->hal_from_customer($c, $customer, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $customer->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');

        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

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

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;


        #unless(defined $resource->{billing_profile_id}) {
        #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id', not defined.");
        #    last;
        #}

        # add product_id just for form check (not part of the actual contract item)
        # and remove it after the check
        #$resource->{product_id} = $product->id;
        
        #$resource->{contact_id} //= undef;
        my $form = $self->get_form($c);
        #$resource->{billing_profile_id} //= undef;
        #$resource->{billing_profiles} //= undef;
        $resource->{contact_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [ "contact_id", "billing_profile_id", "profile_package_id" ],
        );
        #delete $resource->{product_id};

        my $mappings_to_create = [];
        last unless NGCP::Panel::Utils::Contract::prepare_billing_mappings(
            c => $c,
            resource => $resource,
            old_resource => undef,
            mappings_to_create => $mappings_to_create,
            err_code => sub {
                my ($err) = @_;
                #$c->log->error($err);
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
            });
        #delete $resource->{billing_profile_id};
        #delete $resource->{billing_profiles};
        #delete $resource->{billing_profile_definition};
        
        my $product_class = delete $resource->{type};
        #unless( (defined $product_class ) && ($product_class eq "sipaccount" || $product_class eq "pbxaccount") ) {
        #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Mandatory 'type' parameter is empty or invalid, must be 'sipaccount' or 'pbxaccount'.");
        #    last;
        #}
        my $product = $schema->resultset('products')->find({ class => $product_class });
        unless($product) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'type'.");
            last;
        }
        
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        $resource->{create_timestamp} = $now;
        $resource->{modify_timestamp} = $now;
        my $customer;

       

        try {
            $customer = $schema->resultset('contracts')->create($resource);
        } catch($e) {
            $c->log->error("failed to create customer contract: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create customer.");
            last;
        }

        unless($customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The contact_id is not a valid ngcp:customercontacts item, but an ngcp:systemcontacts item");
            last;
        }
        #if (defined $billing_profile) {
        #    unless($customer->contact->reseller_id == $billing_profile->reseller_id) {
        #        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "The reseller of the contact doesn't match the reseller of the billing profile");
        #        last;
        #    }
        #}
        if($customer->invoice_template_id && 
           $customer->invoice_template->reseller_id != $customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'invoice_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
        if($customer->subscriber_email_template_id && 
           $customer->subscriber_email_template->reseller_id != $customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_email_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
        if($customer->passreset_email_template_id && 
           $customer->passreset_email_template->reseller_id != $customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'passreset_email_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }
        if($customer->invoice_email_template_id && 
           $customer->invoice_email_template->reseller_id != $customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'invoice_email_template_id', doesn't exist for reseller assigned to customer contact");
            return;
        }

        try {
            foreach my $mapping (@$mappings_to_create) {
                $customer->billing_mappings->create($mapping); 
                #$customer->create_related('billing_mappings',$mapping);                
            }
            #$customer->billing_mappings_actual->search({},{bind => [ ( $schema->storage->datetime_parser->format_datetime(NGCP::Panel::Utils::DateTime::current_local) ) x 2]})->first->get_inflated_columns()
            $customer = $self->customer_by_id($c, $customer->id);
            NGCP::Panel::Utils::Contract::create_contract_balance(
                c => $c,
                profile => $customer->billing_mappings->find($customer->get_column('bmid'))->billing_profile,
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
            return $self->hal_from_customer($c,$_customer,$form); }); #$form

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $customer->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return;
}

# vim: set tabstop=4 expandtab:
