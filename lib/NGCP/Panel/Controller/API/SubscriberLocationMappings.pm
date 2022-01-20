package NGCP::Panel::Controller::API::SubscriberLocationMappings;
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
    return 'Defines location mappings for subscribers to terminate calls on other registrations.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for location mappings of a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'voip_subscriber.id' => $q };
                },
                second => sub {
                    return { join => { subscriber => 'voip_subscriber' } };
                },
            },
        },
        {
            param => 'external_id',
            description => 'Filter for location mappings matching the provided external_id',
            query_type => 'string_eq',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SubscriberLocationMappings/;

sub resource_name {
    return 'subscriberlocationmappings';
}

sub dispatch_path {
    return '/api/subscriberlocationmappings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberlocationmappings';
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

        my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'me.id' => $resource->{subscriber_id}
        });
        if($c->user->roles eq "reseller") {
            $sub_rs = $sub_rs->search({
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                join => { contract => 'contact' },
            });
        }
        my $sub = $sub_rs->first;
        unless($sub && $sub->provisioning_voip_subscriber) {
            $c->log->error("invalid subscriber_id '$$resource{subscriber_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber does not exist");
            last;
        }

        $resource->{subscriber_id} = $sub->provisioning_voip_subscriber->id;
        $resource->{location} //= '';
        $resource->{caller_pattern} //= '.+';
        $resource->{callee_pattern} //= '.+';

        my $item;
        try {
            $item = $c->model('DB')->resultset('voip_subscriber_location_mappings')->create($resource);
        } catch($e) {
            $c->log->error("failed to create location mapping: " . $c->qs($e)); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create location mapping.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_item = $self->item_by_id($c, $item->id);
            return $self->hal_from_item($c, $_item, $form); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
