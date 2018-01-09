package NGCP::Panel::Controller::API::Subscribers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::Events qw();
use UUID;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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
                    return \['exists ( select subscriber_id, group_concat(concat(cc,ac,sn)) as aliases from billing.voip_numbers voip_subscriber_aliases_csv where voip_subscriber_aliases_csv.`subscriber_id` = `me`.`id` group by subscriber_id having aliases like ?)', [ {} => '%'.$q.'%'] ];
                },
                second => sub {
                    return { };
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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::Subscribers/;

sub resource_name{
    return 'subscribers';
}
sub dispatch_path{
    return '/api/subscribers/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscribers';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
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
    return 1;
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
        my ($form) //= $self->get_form($c);
        for my $subscriber (@$subscribers) {
            my $contract = $subscriber->contract;
            NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
                contract => $contract,
                now => $now) if !exists $contract_map{$contract->id}; #apply underrun lock level
            $contract_map{$contract->id} = 1;
            my $resource = $self->resource_from_item($c, $subscriber, $form);
            push @embedded, $self->hal_from_item($c, $subscriber, $resource, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
            );
        }
        $self->delay_commit($c,$guard);
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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

    if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
    } elsif($c->user->roles eq "subscriber") {
        $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
        return;
    } elsif($c->user->roles eq "subscriberadmin") {
        unless($c->config->{features}->{cloudpbx}) {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            return;
        }
        my $customer = $self->get_customer($c, $c->user->account_id);
        if($customer->get_column('product_class') ne 'pbxaccount') {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            return;
        }
    }

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
        my $preferences = $r->{preferences};
        my $groups = $r->{groups};
        my $groupmembers = $r->{groupmembers};
        $resource = $r->{resource};

        try {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);

            my @events_to_create = ();
            my $event_context = { events_to_create => \@events_to_create };
            $subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                c => $c,
                schema => $schema,
                contract => $r->{customer},
                params => $resource,
                preferences => $preferences,
                admin_default => 0,
                event_context => $event_context,
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
            $c->log->error("failed to create subscriber: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber: $e");
            last;
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return;
}

1;

# vim: set tabstop=4 expandtab:
