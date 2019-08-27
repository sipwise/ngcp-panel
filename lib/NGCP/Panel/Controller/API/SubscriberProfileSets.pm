package NGCP::Panel::Controller::API::SubscriberProfileSets;
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
    return 'Defines subscriber profile sets allowing the admin or subscriber to choose from profiles within this set, which in turn define the available features for a subscriber.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for profile sets belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for profile sets with a specific name',
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

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SubscriberProfileSets/;

sub resource_name{
    return 'subscriberprofilesets';
}

sub dispatch_path{
    return '/api/subscriberprofilesets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberprofilesets';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        #todo - is it really necessary? move to item_rs?
        $items = $items->search_rs({}, {prefetch => ['reseller']});
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
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
        $c->log->error("profile set creation by reseller forbidden via config");
        $self->error($c, HTTP_FORBIDDEN, "Subscriber profile set creation forbidden for resellers.");
        return;
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

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

        my $item;

        $item = $c->model('DB')->resultset('voip_subscriber_profile_sets')->find({
            reseller_id => $resource->{reseller_id},
            name => $resource->{name},
        });
        if($item) {
            $c->log->error("subscriber profile set with name '$$resource{name}' already exists for reseller_id '$$resource{reseller_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber profile set with this name already exists for this reseller");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('voip_subscriber_profile_sets')->create($resource);
        } catch($e) {
            $c->log->error("failed to create subscriber profile set: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create subscriber profile set.");
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
