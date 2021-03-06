package NGCP::Panel::Controller::API::RtcSessions;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);



sub api_description {
    return 'Show a collection of RTC sessions, belonging to a specific subscriber.';
}

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub query_params {
    return [];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::RtcSessions/;

sub resource_name{
    return 'rtcsessions';
}

sub dispatch_path{
    return '/api/rtcsessions/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-rtcsessions';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriber subscriberadmin/],
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
            my $hal = $self->hal_from_item($c, $subscriber);
            next unless $hal;
            push @embedded, $hal;
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

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;  # TODO: ?
        } else {
            $resource->{subscriber_id} = $c->user->voip_subscriber->id;
        }

        my $subscriber_item = $c->model('DB')->resultset('voip_subscribers')->search_rs({
                id => $resource->{subscriber_id},
            })->first;

        unless ($subscriber_item) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Subscriber invalid or not found.");
            last;
        }

        # my $form = $self->get_form();
        # $resource->{reseller_id} //= undef;
        # last unless $self->validate_form(
        #     c => $c,
        #     resource => $resource,
        #     form => $form,
        # );

        my $session_item = NGCP::Panel::Utils::Rtc::create_rtc_session(
            config => $c->config,
            subscriber_item => $subscriber_item,
            resource => $resource,
            err_code => sub {
                my ($msg, $debug) = @_;
                $c->log->debug($debug) if $debug;
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $msg);
                return;
            });
        last unless $session_item;

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $session_item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
