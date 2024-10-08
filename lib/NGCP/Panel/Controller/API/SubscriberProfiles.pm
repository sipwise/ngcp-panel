package NGCP::Panel::Controller::API::SubscriberProfiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


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
            query_type => 'wildcard',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SubscriberProfiles/;

sub resource_name{
    return 'subscriberprofiles';
}

sub dispatch_path{
    return '/api/subscriberprofiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberprofiles';
}

__PACKAGE__->set_config({
    allowed_roles => {
        'Default' => [qw/admin reseller ccareadmin ccare/],
        'GET'     => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
    },
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        $self->expand_collection_fields($c, \@embedded);
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

    if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
        $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
        return;
    }

    if($c->user->roles eq "reseller" && !$c->config->{profile_sets}->{reseller_edit}) {
        $self->error($c, HTTP_FORBIDDEN, "Subscriber profile creation forbidden for resellers.",
                     "profile creation by reseller forbidden via config");
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

        $resource->{set_id} = delete $resource->{profile_set_id};

        my $set = $c->model('DB')->resultset('voip_subscriber_profile_sets');
        if($c->user->roles eq "reseller") {
            $set = $set->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        $set = $set->find($resource->{set_id});
        unless($set) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'profile_set_id', does not exist",
                         "subscriber profile set with id '$$resource{set_id}' does not exist");
            last;
        }

        my $item;
        $item = $set->voip_subscriber_profiles->find({
            name => $resource->{name},
        });
        if($item) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                         "Subscriber profile with this name already exists for this profile set",
                         "subscriber profile with name '$$resource{name}' already exists for profile_set_id '$$resource{set_id}'");
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
                    attribute => { -in => [qw/cfu cft cfna cfb cfs cfr cfo/] },
                },
                ],
            });
            foreach my $a(@{ $attributes }) {
                my $meta = $meta_rs->find({ attribute => $a });
                next unless $meta;
                $item->profile_attributes->create({ attribute_id => $meta->id });
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber profile.", $e);
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

1;

# vim: set tabstop=4 expandtab:
