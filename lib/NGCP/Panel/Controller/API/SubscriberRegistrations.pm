package NGCP::Panel::Controller::API::SubscriberRegistrations;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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
            my $halitem = $self->hal_from_item($c, $item, $form);
            next unless($halitem);
            push @embedded, $halitem;
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
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





sub POST :Allow {
    my ($self, $c) = @_;

    {
        my ($item, $resource);

        $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        my $create = 1;

        my ($guard, $txn_ok) = ($c->model('DB')->txn_scope_guard, 0);
        {
            $self->update_item($c, undef, undef, $resource, $form, $create);

            $guard->commit;
            $txn_ok = 1;
        }
        last unless $txn_ok;

        $item = $self->fetch_item($c, $resource, $form, $item);
        last unless $item;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}



1;

# vim: set tabstop=4 expandtab:
