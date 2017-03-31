package NGCP::Panel::Controller::API::SpeedDials;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Preferences;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use UUID;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Show a collection of speeddials, belonging to a specific subscriber. The collection\'s id corresponds to the subscriber\'s id.';
};

sub query_params {
    return [
        {
            param => 'nonempty',
            description => 'Filter for subscribers with nonempty speeddials',
            query => {
                first => sub {
                    return unless shift;
                    { 'voip_speed_dials.id' => { '!=' => undef } };
                },
                second => sub {
                    return unless shift;
                    { prefetch => { provisioning_voip_subscriber => 'voip_speed_dials' } };
                },
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::SpeedDials/;

sub resource_name{
    return 'speeddials';
}
sub dispatch_path{
    return '/api/speeddials/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-speeddials';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
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
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $subscribers = $self->item_rs($c);
        (my $total_count, $subscribers) = $self->paginate_order_collection($c, $subscribers);
        my (@embedded, @links);
        for my $subscriber ($subscribers->all) {
            push @embedded, $self->hal_from_item($c, $subscriber);
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
