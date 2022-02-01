package NGCP::Panel::Controller::API::AutoAttendants;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use UUID;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Show a collection of auto attendant slots, belonging to a specific subscriber.';
};

sub query_params {
    return [
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::AutoAttendants/;

sub resource_name{
    return 'autoattendants';
}

sub dispatch_path{
    return '/api/autoattendants/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-autoattendants';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $subscribers = $self->item_rs($c);
        (my $total_count, $subscribers, my $subscribers_rows) = $self->paginate_order_collection($c, $subscribers);
        my (@embedded, @links);
        for my $subscriber (@$subscribers_rows) {
            push @embedded, $self->hal_from_item($c, $subscriber);
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

1;

# vim: set tabstop=4 expandtab:
