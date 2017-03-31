package NGCP::Panel::Controller::API::PeeringInboundRules;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Peering;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines inbound peering rules.';
};

sub query_params {
    return [
        {
            param => 'group_id',
            description => 'Filter for peering group',
            query => {
                first => sub {
                    my $q = shift;
                    { group_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'field',
            description => 'Filter for peering rules field (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { field => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'enabled',
            description => 'Filter for peering rules enabled flag',
            query => {
                first => sub {
                    my $q = shift;
                    { enabled =>  $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::PeeringInboundRules/;

sub resource_name{
    return 'peeringinboundrules';
}
sub dispatch_path{
    return '/api/peeringinboundrules/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-peeringinboundrules';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
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
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
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

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;
        my $item;
        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [qw/group_id/],
        );
        unless($c->model('DB')->resultset('voip_peer_groups')->find($resource->{group_id})) {
            $c->log->error("peering group $$resource{group_id} does not exist");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering group $$resource{group_id} does not exist");
            last;
        }
        my $dup_item = $c->model('DB')->resultset('voip_peer_inbound_rules')->find({
            group_id => $resource->{group_id},
            field => $resource->{field},
            pattern => $resource->{pattern},
            reject_code => $resource->{reject_code},
            reject_reason => $resource->{reject_reason},
            enabled => $resource->{enabled},
            priority => $resource->{priority},
        });
        if($dup_item) {
            $c->log->error("peering rule already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule already exists");
            last;
        }
        my $prio_rs = $c->model('DB')->resultset('voip_peer_inbound_rules')->search({
                group_id => $resource->{group_id},
                priority => $resource->{priority},
            },
            {}
        );
        if($prio_rs->count) {
            $c->log->error("peering rule priority $$resource{priority} already exists for this group");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule priority $$resource{priority} already exists for this group");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('voip_peer_inbound_rules')->create($resource);
            $item->group->update({
                has_inbound_rules => 1
            });
        } catch($e) {
            $c->log->error("failed to create peering rule: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering rule.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
