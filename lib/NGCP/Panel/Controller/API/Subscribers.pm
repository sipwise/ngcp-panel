package NGCP::Panel::Controller::API::Subscribers;
use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use UUID;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines an actual user who can log into the web panel, register devices via SIP and/or '.
        'XMPP and place and receive calls via SIP. A subscriber always belongs to a '.
        '<a href="#customers">Customer</a> and is placed inside a <a href="#domains">Domain</a>.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
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
                    return { 'voip_subscriber_aliases_csv.aliases' => { like => '%'.$q.'%' } };
                },
                second => sub {
                    return { join => 'voip_subscriber_aliases_csv' };
                },
            },
        },
    ]},
);

with 'NGCP::Panel::Role::API::Subscribers';

class_has('resource_name', is => 'ro', default => 'subscribers');
class_has('dispatch_path', is => 'ro', default => '/api/subscribers/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-subscribers');

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
        my $subscribers = $self->item_rs($c);
        (my $total_count, $subscribers) = $self->paginate_order_collection($c, $subscribers);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $subscriber ($subscribers->all) {
            my $resource = $self->resource_from_item($c, $subscriber, $form);
            push @embedded, $self->hal_from_item($c, $subscriber, $resource, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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

    my $schema = $c->model('DB');
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
        $resource = $r->{resource};

        try {
            my ($uuid_bin, $uuid_string);
            UUID::generate($uuid_bin);
            UUID::unparse($uuid_bin, $uuid_string);

            $subscriber = NGCP::Panel::Utils::Subscriber::create_subscriber(
                c => $c,
                schema => $schema,
                contract => $r->{customer},
                params => $resource,
                preferences => $preferences,
                admin_default => 0,
            );
            if($resource->{status} eq 'locked') {
                NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                    c => $c,
                    prov_subscriber => $subscriber->provisioning_voip_subscriber,
                    level => $resource->{lock} || 4,
                );
            }
            NGCP::Panel::Utils::Subscriber::update_subscriber_numbers(
                c              => $c,
                schema         => $schema,
                alias_numbers  => $alias_numbers,
                reseller_id    => $customer->contact->reseller_id,
                subscriber_id  => $subscriber->id,
            );
            $subscriber->discard_changes; # reload row because of new number

            foreach my $group(@{ $groups }) {
                $subscriber->provisioning_voip_subscriber->voip_pbx_groups->create({
                    group_id => $group->provisioning_voip_subscriber->id,
                });
                NGCP::Panel::Utils::Subscriber::update_pbx_group_prefs(
                    c => $c,
                    schema => $schema,
                    old_group_id => undef,
                    new_group_id => $group->id,
                    username => $subscriber->username,
                    domain => $subscriber->domain->domain,
                    group_rs => $schema->resultset('voip_subscribers')->search({
                        contract_id => $customer->id,
                        status => { '!=' => 'terminated' },
                    }),
                );
            }

        } catch(DBIx::Class::Exception $e where { /Duplicate entry '([^']+)' for key 'number_idx'/ }) {
            $e =~ /Duplicate entry '([^']+)' for key 'number_idx'/;
            $c->log->error("failed to create subscriber, number $1 already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Number '$1' already exists.");
            last;
        } catch($e) {
            $c->log->error("failed to create subscriber: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber.");
            last;
        }


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

# vim: set tabstop=4 expandtab:
