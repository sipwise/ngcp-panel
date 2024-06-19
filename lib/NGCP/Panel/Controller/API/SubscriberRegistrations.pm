package NGCP::Panel::Controller::API::SubscriberRegistrations;
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
    return 'Defines registered contacts of subscribers.';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for registrations of a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    my $c = shift;
                    my %wheres = ();
                    if( $c->config->{features}->{multidomain}) {
                        $wheres{'domain.id'} = { -ident => 'subscriber.domain_id' };
                    }

                    my $h = 
                    return {
                        'voip_subscriber.id' => $q,
                        %wheres,
                    };
                },
                second => sub {
                    my $q = shift;
                    my $c = shift;
                    my @joins = ();
                    if( $c->config->{features}->{multidomain}) {
                        push @joins, 'domain' ;
                    }
                    return {
                        join => [{ subscriber => 'voip_subscriber' },@joins]
                    };
                },
            },
        },
    ];
};

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'contact' => 'contact',
        'expires' => 'expires',
        'id'      => 'id',
        'path'    => 'path',
        'q'       => 'q',
        'user_agent'    => 'user_agent',
    };
    return $cols;
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SubscriberRegistrations/;

sub resource_name{
    return 'subscriberregistrations';
}

sub dispatch_path{
    return '/api/subscriberregistrations/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberregistrations';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriber subscriberadmin/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c, undef, {page => $page, rows => $rows});
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $item (@$items_rows) {
            my $halitem = $self->hal_from_item($c, $item, $form);
            next unless($halitem);
            push @embedded, $halitem;
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%s', $c->request->path, $item->id),
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

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;

    my $create = 1;

    return unless $self->update_item($c, "new", undef, $resource, $form, $create);

    return $self->fetch_item($c, $resource, $form, $item);
}

1;

# vim: set tabstop=4 expandtab:
