package NGCP::Panel::Controller::API::Reminders;
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
    return 'Defines reminder (wake-up call) settings for subscribers.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for reminders of a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'voip_subscriber.id' => $q };
                },
                second => sub {
                    return {
                        join => { subscriber => 'voip_subscriber' }
                    };
                },
            },
        },
        {
            param => 'active',
            description => 'Filter for active or inactive reminders (0|1)',
            query => {
                first => sub {
                    my $q = shift;
                    return { active => !!$q };
                },
                second => sub {
                    return { };
                },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Reminders/;

sub resource_name{
    return 'reminders';
}

sub dispatch_path{
    return '/api/reminders/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-reminders';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
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

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        $form->field('subscriber_id')->required(0) if ($c->user->roles eq "subscriber");
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $sub = $self->get_subscriber_by_id($c, $resource->{subscriber_id} );
        return unless $sub;
        $resource->{subscriber_id} = $sub->provisioning_voip_subscriber->id;

        my $allowed_prefs = NGCP::Panel::Utils::Preferences::get_subscriber_allowed_prefs(
            c => $c,
            prov_subscriber => $sub->provisioning_voip_subscriber,
            pref_list => ['reminder'],
        );
        unless ($allowed_prefs->{reminder}) {
            $c->log->error("Not permitted to create reminder for this subscriber via subscriber profile");
            $self->error($c, HTTP_FORBIDDEN, "Not permitted to create reminder");
            return;
        }

        my $item;
        $item = $c->model('DB')->resultset('voip_reminder')->find({
            subscriber_id => $resource->{subscriber_id},
        });
        if($item) {
            $c->log->error("reminder already exists for subscriber_id '$$resource{subscriber_id}'"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Reminder already exists for this subscriber");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('voip_reminder')->create($resource);
        } catch($e) {
            $c->log->error("failed to create reminder: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create reminder.");
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
