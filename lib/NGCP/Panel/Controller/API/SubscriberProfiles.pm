package NGCP::Panel::Controller::API::SubscriberProfiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
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
    return 'Defines subscriber profiles which specify the available features for a subscriber.';
};

sub query_params {
    return [
        {
            param => 'profile_set_id',
            description => 'Filter for profiles  belonging to a specific profile set',
            query => {
                first => sub {
                    my $q = shift;
                    { set_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for profile with a specific name',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.name' => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::SubscriberProfiles/;

sub resource_name{
    return 'subscriberprofiles';
}
sub dispatch_path{
    return '/api/subscriberprofiles/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberprofiles';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
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

    if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit}) {
        $c->log->error("profile creation by reseller forbidden via config");
        $self->error($c, HTTP_FORBIDDEN, "Subscriber profile creation forbidden for resellers.");
        return;
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $attributes = delete $resource->{attributes};

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }
        $resource->{set_id} = delete $resource->{profile_set_id};

        my $set = $c->model('DB')->resultset('voip_subscriber_profile_sets');
        if($c->user->roles eq "reseller") {
            $set = $set->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        $set = $set->find($resource->{set_id});
        unless($set) {
            $c->log->error("subscriber profile set with id '$$resource{set_id}' does not exist"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'profile_set_id', does not exist");
            last;
        }

        my $item;
        $item = $set->voip_subscriber_profiles->find({
            name => $resource->{name},
        });
        if($item) {
            $c->log->error("subscriber profile with name '$$resource{name}' already exists for profile_set_id '$$resource{set_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber profile with this name already exists for this profile set");
            last;
        }
        if($resource->{set_default}) {
            $set->voip_subscriber_profiles->update({
                set_default => 0,
            });
        }
        unless($set->voip_subscriber_profiles->count) {
            $resource->{set_default} = 1;
        }

        try {
            $item = $set->voip_subscriber_profiles->create($resource);
            my $meta_rs = $c->model('DB')->resultset('voip_preferences')->search({
                -or => [
                {
                    usr_pref => 1,
                    expose_to_customer => 1,
                },
                {
                    attribute => { -in => [qw/cfu cft cfna cfb cfs/] },
                },
                ],
            });
            foreach my $a(@{ $attributes }) {
                my $meta = $meta_rs->find({ attribute => $a });
                next unless $meta;
                $item->profile_attributes->create({ attribute_id => $meta->id });
            }
        } catch($e) {
            $c->log->error("failed to create subscriber profile: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber profile.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_item = $self->item_by_id($c, $item->id);
            return $self->hal_from_item($c, $_item); });
        
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
