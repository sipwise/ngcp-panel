package NGCP::Panel::Controller::API::RtcSessions;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;


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

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriber subscriberadmin/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);



sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $subscribers = $self->item_rs($c);
        (my $total_count, $subscribers) = $self->paginate_order_collection($c, $subscribers);
        my (@embedded, @links);
        for my $subscriber ($subscribers->all) {
            my $hal = $self->hal_from_item($c, $subscriber);
            next unless $hal;
            push @embedded, $hal;
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subscriber->id),
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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
