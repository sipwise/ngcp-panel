package NGCP::Panel::Controller::API::CallLists;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
use DateTime::TimeZone;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines call lists in simplified form for showing call histories of subscribers.';
};

sub query_params {
    return [
        {
            param => 'tz',
            description => 'Format start_time according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
        {
            param => 'subscriber_id',
            description => 'Filter for calls for a specific subscriber. Either this or customer_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific subscriber in order to properly determine the direction of calls.',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($q);
                if ($subscriber) {
                    my $out_rs = $rs->search_rs({
                        source_user_id => $subscriber->uuid,
                    });
                    my $in_rs = $rs->search_rs({
                        destination_user_id => $subscriber->uuid,
                    });
                    return $out_rs->union_all($in_rs);
                }
                return $rs;
            },
        },
        {
            param => 'customer_id',
            description => 'Filter for calls for a specific customer. Either this or subscriber_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific customer. For calls within the same customer_id, the direction will always be "out".',
            query => {
                first => sub {
                    my $q = shift;
                    return {
                        -or => [
                            'source_account_id' => $q,
                            'destination_account_id' => $q,
                        ],
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'alias_field',
            description => 'Set this parameter for example to "gpp0" if you store alias numbers in the gpp0 preference and want to have that value shown as other CLI for calls from or to such a local subscriber.',
            query => {
                # handled directly in role
                first => sub {},
                second => sub {},
            },
        },
        {
            param => 'status',
            description => 'Filter for calls with a specific status. One of "ok", "busy", "noanswer", "cancel", "offline", "timeout", "other".',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.call_status' => $q,
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'status_ne',
            description => 'Filter for calls not having a specific status. One of "ok", "busy", "noanswer", "cancel", "offline", "timeout", "other".',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.call_status' => { '!=' => $q },
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'rating_status',
            description => 'Filter for calls having a specific rating status. Comma separated list of "ok", "unrated", "failed".',
            query => {
                first => sub {
                    my $q = shift;
                    my @l = split /,/, $q;
                    { 'me.rating_status' => { -in => \@l }};
                },
                second => sub {},
            },
        },
        {
            param => 'rating_status_ne',
            description => 'Filter for calls not having a specific rating status. Comma separated list of "ok", "unrated", "failed".',
            query => {
                first => sub {
                    my $q = shift;
                    my @l = split /,/, $q;
                    { 'me.rating_status' => { -not_in => \@l }};
                },
                second => sub {},
            },
        },
        {
            param => 'type',
            description => 'Filter for calls with a specific type. One of "call", "cfu", "cfb", "cft", "cfna".',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       call_type => $q,
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'type_ne',
            description => 'Filter for calls not having a specific type. One of "call", "cfu", "cfb", "cft", "cfna".',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       call_type => { '!=' => $q },
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'direction',
            description => 'Filter for calls with a specific direction. One of "in", "out".',
            query => {
                first => sub {
                    my ($q, $c) = @_;
                    return unless ($q eq "out" || $q eq "in");
                    my $owner = $c->stash->{owner} // {};
                    if ($owner->{subscriber}) {
                        my $field = ($q eq "out") ? "source_user_id" : "destination_user_id";
                        return {
                            $field => $owner->{subscriber}->uuid,
                        };
                    } elsif ($owner->{customer}) {
                        if ($q eq "out") {
                            return {
                                'source_account_id' => $owner->{customer}->id,
                            };
                        } else {
                            return {
                                'destination_account_id' => $owner->{customer}->id,
                                'source_account_id' => {'!=' => $owner->{customer}->id},
                            };
                        }
                    }
                },
                second => sub {},
            },
        },
        {
            param => 'start_ge',
            description => 'Filter for calls starting greater or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { 'me.start_time' => { '>=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'start_le',
            description => 'Filter for calls starting lower or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    $q .= ' 23:59:59' if($q =~ /^\d{4}\-\d{2}\-\d{2}$/);
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { start_time => { '<=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'call_id',
            description => 'Filter for a particular call_id and sort by call leg depth.',
            query => {
                first => sub {
                    my $q = shift;
                    {
                        call_id => { like => $q.'%' },
                    };
                },
                second => sub {
                    {
                        order_by => \"length(call_id) ASC, start_time ASC",
                    };
                },
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::CallLists/;

sub resource_name{
    return 'calllists';
}
sub dispatch_path{
    return '/api/calllists/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-calllists';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
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
    my $schema = $c->model('DB');
    {
        if($c->req->param('tz') && !DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }

        my $owner = $self->get_owner_data($c, $schema);
        last unless $owner;
        $c->stash(owner => $owner); # for query_param: direction
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        my $href_data = $owner->{subscriber} ?
            "subscriber_id=".$owner->{subscriber}->id :
            "customer_id=".$owner->{customer}->id;
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $owner, $form, $href_data);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d?%s', $c->request->path, $item->id, $href_data),
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s&%s', $c->request->path, $page, $rows, $href_data));
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
    return;
}
1;
# vim: set tabstop=4 expandtab: