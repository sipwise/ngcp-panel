package NGCP::Panel::Controller::API::CallLists;
use Sipwise::Base;
use Moose qw(after augment before extends has inner override super with);

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines call lists in simplified form for showing call histories of subscribers.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'subscriber_id',
            description => 'Filter for calls for a specific subscriber. Either this or customer_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific subscriber in order to properly determine the direction of calls.',
            query => {
                first => sub {
                    my $q = shift;
                    return {
                        -or => [
                            'source_subscriber.id' => $q,
                            'destination_subscriber.id' => $q, 
                        ],
                    };
                },
                second => sub {
                    return {
                        join => ['source_subscriber', 'destination_subscriber'],
                    };
                },
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
                       call_status => $q,
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
                       call_status => { '!=' => $q },
                    };
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
                    if($q eq "out") {
                        {
                           source_user_id => $c->user->uuid,
                        };
                    } elsif($q eq "in") {
                        {
                           destination_user_id => $c->user->uuid,
                        };
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
                    { start_time => { '>=' => $dt->epoch } },
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
                    { start_time => { '<=' => $dt->epoch } },
                },
                second => sub {},
            },
        },
    ]},
);

with 'NGCP::Panel::Role::API::CallLists';

class_has('resource_name', is => 'ro', default => 'calllists');
class_has('dispatch_path', is => 'ro', default => '/api/calllists/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-calllists');

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
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    my $schema = $c->model('DB');
    {
        my $owner = $self->get_owner_data($c, $schema);
        last unless $owner;
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
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}
1;
# vim: set tabstop=4 expandtab:
