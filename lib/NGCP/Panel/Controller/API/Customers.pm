package NGCP::Panel::Controller::API::Customers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD I_GET I_HEAD I_OPTIONS I_PATCH I_PUT I_DELETE /];
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
        {
            param => 'package_id',
            description => 'Filter for customers with specific profile package id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.profile_package_id' => $q };
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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::Customers/;

sub resource_name{
    return 'customers';
}
sub dispatch_path{
    return '/api/customers/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customers';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => ($_ =~ m!^I_!) ? 1 : 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => ($_ =~ s!^I_!!r),
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    #$self->apply_fake_time($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $customers_rs = $self->item_rs($c,$now);
        (my $total_count, $customers_rs) = $self->paginate_order_collection($c, $customers_rs);
        my $customers = NGCP::Panel::Utils::ProfilePackages::lock_contracts(c => $c,
            rs => $customers_rs,
            contract_id_field => 'id');
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $customer (@$customers) {
            push @embedded, $self->hal_from_customer($c, $customer, $form, $now);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $customer->id),
            );
        }
        $self->delay_commit($c,$guard); #potential db write ops in hal_from
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');

        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = NGCP::Panel::Utils::DataHal->new(
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
        Allow => join(', ', @{ $allowed_methods }),
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

        my $form = $self->get_form($c);
        $resource->{contact_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [ "contact_id", "billing_profile_id", "profile_package_id", "invoice_template_id", "invoice_email_template_id", "passreset_email_template_id", "subscriber_email_template_id" ],
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

        my $product_class = delete $resource->{type};
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
        #todo: strange: why do we check this after customer creation?
        my $tmplfields = $self->get_template_fields_spec();
        foreach my $field (keys %$tmplfields){
            my $field_table_rel = $tmplfields->{$field}->[1];
            if($customer->$field() &&
               $customer->$field_table_rel()->reseller_id != $customer->contact->reseller_id) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid '$field', doesn't exist for the reseller assigned to customer contact");
                return;
            }
        }

        try {
            foreach my $mapping (@$mappings_to_create) {
                $customer->billing_mappings->create($mapping);
            }
            $customer = $self->customer_by_id($c, $customer->id,$now);
            NGCP::Panel::Utils::ProfilePackages::create_initial_contract_balances(c => $c,
                contract => $customer,
                #bm_actual => $customer->billing_mappings->find($customer->get_column('bmid')),
            );
            #NGCP::Panel::Utils::Contract::create_contract_balance(
            #    c => $c,
            #    profile => $customer->billing_mappings->find($customer->get_column('bmid'))->billing_profile,
            #    contract => $customer,
            #);
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

sub I_GET :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        if($c->user->roles eq "subscriberadmin") {
            unless($c->user->account_id == $id) {
                $self->error($c, HTTP_FORBIDDEN, "Invalid customer id");
                return;
            }
        }
        last unless $self->valid_id($c, $id);
        my $customer = $self->customer_by_id($c, $id);
        last unless $self->resource_exists($c, customer => $customer);

        my $hal = $self->hal_from_customer($c, $customer, undef, NGCP::Panel::Utils::DateTime::current_local);
        $guard->commit; #potential db write ops in hal_from

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub I_HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub I_OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub I_PATCH :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $customer = $self->customer_by_id($c, $id, $now);
        last unless $self->resource_exists($c, customer => $customer);

        my $old_resource = { $customer->get_inflated_columns };
        delete $old_resource->{profile_package_id};
        my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
        $old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id;
        $old_resource->{billing_profile_definition} = undef;

        my $resource = $self->apply_patch($c, $old_resource, $json, sub {
            my ($missing_field,$entity) = @_;
            if ($missing_field eq 'billing_profiles') {
                $entity->{billing_profiles} = NGCP::Panel::Utils::Contract::resource_from_future_mappings($customer);
                $entity->{billing_profile_definition} //= 'profiles';
            } elsif ($missing_field eq 'profile_package_id') {
                $entity->{profile_package_id} = $customer->profile_package_id;
                $entity->{billing_profile_definition} //= 'package';
            }
        });
        last unless $resource;

        my $form = $self->get_form($c);
        $customer = $self->update_customer($c, $customer, $old_resource, $resource, $form, $now);
        last unless $customer;

        my $hal = $self->hal_from_customer($c, $customer, $form, $now);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_customer($c, $customer, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub I_PUT :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $customer = $self->customer_by_id($c, $id, $now);
        last unless $self->resource_exists($c, customer => $customer);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $customer->get_inflated_columns };

        my $form = $self->get_form($c);
        $customer = $self->update_customer($c, $customer, $old_resource, $resource, $form, $now);
        last unless $customer;

        my $hal = $self->hal_from_customer($c, $customer, $form,$now);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_customer($c, $customer, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

=pod
# we don't allow to delete customers
sub I_DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $customer = $self->customer_by_id($c, $id);
        last unless $self->resource_exists($c, customer => $customer);

        # TODO: do we want to prevent deleting used customers?
        #my $customer_count = $c->model('DB')->resultset('customers')->search({
        #    contact_id => $id
        #});
        #if($customer_count > 0) {
        #    $self->error($c, HTTP_LOCKED, "Contact is still in use.");
        #    last;
        #} else {
            $customer->delete;
        #}
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}
=cut

sub end : Private {
    my ($self, $c) = @_;

    #$self->reset_fake_time($c);
    $self->log_response($c);
    return;
}

1;

# vim: set tabstop=4 expandtab:
