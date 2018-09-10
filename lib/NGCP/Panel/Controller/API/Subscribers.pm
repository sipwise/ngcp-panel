package NGCP::Panel::Controller::API::Subscribers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Subscribers/;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Events qw();
use UUID;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines an actual user who can log into the web panel, register devices via SIP and/or '.
        'XMPP and place and receive calls via SIP. A subscriber always belongs to a '.
        '<a href="#customers">Customer</a> and is placed inside a <a href="#domains">Domain</a>.';
}

sub documentation_sample_update {
    return { "domain_id" => 4,
       "password" => "test",
       "username" => "test",
    };
}

sub query_params {
    my $params = [
        {
            param => 'profile_id',
            description => 'Search for subscribers having a specific subscriber profile',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'provisioning_voip_subscriber.profile_id' => $q };
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => 'username',
            description => 'Search for specific SIP username',
            query => {
                first => sub {
                    my $q = shift;
                    return { username => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'webusername',
            description => 'Search for specific webuser login credentials (exact match)',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'provisioning_voip_subscriber.webusername' => $q };
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => 'webpassword',
            description => 'Search for specific webuser login password (exact match)',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'provisioning_voip_subscriber.webpassword' => $q };
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => 'domain',
            description => 'Filter for subscribers in specific domain',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'domain.domain' => { like => $q } };
                },
                second => sub {
                    my $q = shift;
                    return { 'join' => 'domain' };
                },
            },
        },
        {
            param => 'customer_id',
            description => 'Filter for subscribers of a specific customer.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contract_id' => $q };
                },
                second => sub {
                    return { };
                },
            },
        },
        {
            param => 'customer_external_id',
            description => 'Filter for subscribers of a specific customer external_id.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contract.external_id' => { like => $q } };
                },
                second => sub {
                    return { join => 'contract' };
                },
            },
        },
        {
            param => 'subscriber_external_id',
            description => 'Filter for subscribers by subscriber\'s external_id.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.external_id' => { like => $q } };
                },
                second => sub {
                    return { };
                },
            },
        },
        {
            param => 'is_pbx_group',
            description => 'Filter for subscribers who are (not) pbx_groups.',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        return { 'provisioning_voip_subscriber.is_pbx_group' => 1 };
                    } else {
                        return { 'provisioning_voip_subscriber.is_pbx_group' => 0 };
                    }
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => 'is_admin',
            description => 'Filter for subscribers who are (not) pbx subscriber admins.',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        return { 'provisioning_voip_subscriber.admin' => 1 };
                    } else {
                        return { 'provisioning_voip_subscriber.admin' => 0 };
                    }
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => 'is_pbx_pilot',
            description => 'Filter for subscribers who are pbx pilot subscribers.',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        return { 'provisioning_voip_subscriber.is_pbx_pilot' => 1 };
                    } else {
                        return { 'provisioning_voip_subscriber.is_pbx_pilot' => 0 };
                    }
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => 'alias',
            description => 'Filter for subscribers who has specified alias.',
            query => {
                first => sub {
                    my $q = shift;
                    {
                        'voip_dbaliases.username' => { like => '%'.$q.'%' },
                    };
                },
                second => sub {
                    {
                        join => { 'provisioning_voip_subscriber' => 'voip_dbaliases' },
                        distinct => 1,
                    };
                },
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for subscribers of customers belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => sub {
                    { join => { 'contract' => 'contact' } };
                },
            },
        },
        {
            param => 'contact_id',
            description => 'Filter for subscribers of contracts with a specific contact id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contract.contact_id' => $q };
                },
                second => sub {},
            },
        },
    ];
    foreach my $field (qw/create_timestamp modify_timestamp/){
        push @$params, {
            param => $field.'_gt',
            description => 'Filter for subscriber with '.$field.' greater then specified value',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'provisioning_voip_subscriber.'.$field => { '>=' => $q } };
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        },
        {
            param => $field.'_lt',
            description => 'Filter for subscriber with '.$field.' less then specified value',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'provisioning_voip_subscriber.'.$field => { '<=' => $q } };
                },
                second => sub {
                    return { join => 'provisioning_voip_subscriber' };
                },
            },
        };
    }
    return $params;
}

sub order_by_cols {
    return
        { create_timestamp => 'provisioning_voip_subscriber.create_timestamp' },
        {
            columns_are_additional => 1,
            create_timestamp => {
                join => 'provisioning_voip_subscriber',
            },
        };
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');
    my $guard = $schema->txn_scope_guard;
    {
        my $subscribers_rs = $self->item_rs($c);
        (my $total_count, $subscribers_rs) = $self->paginate_order_collection($c, $subscribers_rs);
        my $subscribers = NGCP::Panel::Utils::ProfilePackages::lock_contracts(c => $c,
            rs => $subscribers_rs,
            contract_id_field => 'contract_id');
        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my (@embedded, @links, %contract_map);
        my ($form) = $self->get_form($c);
        for my $subscriber (@$subscribers) {
            my $contract = $subscriber->contract;
            NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $contract,
                now => $now) if !exists $contract_map{$contract->id}; #apply underrun lock level
            $contract_map{$contract->id} = 1;
            my $resource = $self->resource_from_item($c, $subscriber, $form);
            push @embedded, $self->hal_from_item($c, $subscriber, $resource, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
            );
        }
        $self->delay_commit($c,$guard);
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
use Data::Dumper;
sub POST :Allow {
    my ($self, $c) = @_;


    my $schema = $c->model('DB');
    $schema->set_transaction_isolation('READ COMMITTED');
    my $guard = $schema->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $r = $self->prepare_resource($c, $schema, $resource);
        last unless($r);
        my $subscriber;
        my $customer = $r->{customer};
        my $alias_numbers = $r->{alias_numbers};
            $c->log->debug("IN POST 1 ------------------------------");
            $c->log->debug(Dumper($alias_numbers));
        my $preferences = $r->{preferences};
        my $groups = $r->{groups};
        my $groupmembers = $r->{groupmembers};
        $resource = $r->{resource};
        my $error_info = { extended => {} };

        try {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);

            my @events_to_create = ();
            my $event_context = { events_to_create => \@events_to_create };
            $subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                c             => $c,
                schema        => $schema,
                contract      => $r->{customer},
                params        => $resource,
                preferences   => $preferences,
                admin_default => 0,
                event_context => $event_context,
                error         => $error_info,
            );
            if($resource->{status} eq 'locked') {
                NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                    c => $c,
                    prov_subscriber => $subscriber->provisioning_voip_subscriber,
                    level => $resource->{lock} || 4,
                );
            } else {
                NGCP::Panel::Utils::ProfilePackages::underrun_lock_subscriber(c => $c, subscriber => $subscriber);
            }
            use irka;
            irka::loglong($alias_numbers);
            $c->log->debug("IN POST 9 ------------------------------");
            $c->log->debug(Dumper($alias_numbers));
            NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                c              => $c,
                schema         => $schema,
                alias_numbers  => $alias_numbers,
                reseller_id    => $customer->contact->reseller_id,
                subscriber_id  => $subscriber->id,
            );
            $subscriber->discard_changes; # reload row because of new number
            NGCP::Panel::Utils::Subscriber::manage_pbx_groups(
                c            => $c,
                schema       => $schema,
                groups       => $groups,
                groupmembers => $groupmembers,
                customer     => $customer,
                subscriber   => $subscriber,
            );
            NGCP::Panel::Utils::Events::insert_deferred(
                c => $c, schema => $schema,
                events_to_create => \@events_to_create,
            );
        } catch(DBIx::Class::Exception $e where { /Duplicate entry '([^']+)' for key 'number_idx'/ }) {
            $e =~ /Duplicate entry '([^']+)' for key 'number_idx'/;
            $c->log->error("failed to create subscriber, number $1 already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number '$1' already exists.");
            last;
        } catch($e) {
            if (ref $error_info->{extended} eq 'HASH' && $error_info->{extended}->{response_code}) {
                $c->log->error($error_info->{extended}->{error}); # TODO: user, message, trace, ...
                $self->error($c, $error_info->{extended}->{response_code}, $error_info->{extended}->{description});
                last;
            } else {
                $c->log->error("failed to create subscriber: $e"); # TODO: user, message, trace, ...
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber: $e");
                last;
            }
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my ($_form) = $self->get_form($c);
            my $_subscriber = $self->item_by_id($c, $subscriber->id);
            my $_resource = $self->resource_from_item($c, $_subscriber, $_form);
            return $self->hal_from_item($c,$_subscriber,$_resource,$_form); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $subscriber->id));
        $c->response->body(q());
    }
    return;
}
1;

# vim: set tabstop=4 expandtab:
