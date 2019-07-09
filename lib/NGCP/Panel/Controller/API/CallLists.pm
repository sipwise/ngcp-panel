package NGCP::Panel::Controller::API::CallLists;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::API::Calllist;
use DateTime::TimeZone;
use NGCP::Panel::Utils::CallList qw();

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
            param => 'use_owner_tz',
            description => 'Format start_time according to the filtered customer\'s/subscribers\'s inherited time zone.',
        },
        {
            param => 'subscriber_id',
            description => 'Filter for calls for a specific subscriber. Either this or customer_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific subscriber in order to properly determine the direction of calls.',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                if ($c->user->roles ne "subscriber") {
                    my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($q);
                    if ($subscriber) {
                        my $out_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            source_user_id => $subscriber->uuid,
                        }),NGCP::Panel::Utils::CallList::SUPPRESS_OUT);
                        my $in_rs = NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            destination_user_id => $subscriber->uuid,
                            source_user_id => { '!=' => $subscriber->uuid },
                        }),NGCP::Panel::Utils::CallList::SUPPRESS_IN);
                        return $out_rs->union_all($in_rs);
                    }
                }
                return $rs;
            },
        },
        {
            param => 'customer_id',
            description => 'Filter for calls for a specific customer. Either this or subscriber_id is mandatory if called by admin, reseller or subscriberadmin to filter list down to a specific customer. For calls within the same customer_id, the direction will always be "out".',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                if ($c->user->roles ne "subscriber" and $c->user->roles ne "subscriberadmin" and not exists $c->req->query_params->{subscriber_id}) {
                    return NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$rs->search_rs({
                            -or => [
                                'source_account_id' => $q,
                                'destination_account_id' => $q,
                            ],
                        },undef),NGCP::Panel::Utils::CallList::SUPPRESS_INOUT);
                }
                return $rs;
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
            description => 'Filter for calls with a specific type. One of "call", "cfu", "cfb", "cft", "cfna", "cfs", "cfr", "cfo".',
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
            description => 'Filter for calls not having a specific type. One of "call", "cfu", "cfb", "cft", "cfna", "cfs", "cfr", "cfo".',
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
            param => 'init_ge',
            description => 'Filter for calls initiated greater or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { 'me.init_time' => { '>=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'init_le',
            description => 'Filter for calls initiated lower or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    $q .= ' 23:59:59' if($q =~ /^\d{4}\-\d{2}\-\d{2}$/);
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { init_time => { '<=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'call_id',
            description => 'Filter for a particular call_id prefix and sort by call leg depth.',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                return $rs->search_rs({
                    call_id => { like => $q.'%' },
                },{
                    order_by => { '-asc' => [ \'length(call_id)', 'start_time', ], },
                });
            },
        },
        {
            param => 'own_cli',
            description => 'Filter calls by a specific number that is a part of in or out calls.',
            query => {
                first => sub {
                    my ($q,$c) = @_;
                    my $owner = $c->stash->{owner} // {};
                    return unless $owner;
                    if ($owner->{subscriber}) {
                        return {
                            -or => [
                                { source_cli => $q,
                                  source_user_id => $owner->{subscriber}->uuid,
                                },
                                { destination_user_in => $q,
                                  destination_user_id => $owner->{subscriber}->uuid,
                                },
                            ],
                        };
                    } elsif ($owner->{customer}) {
                        return {
                            -or => [
                                { source_cli => $q,
                                  source_account_id => $owner->{customer}->id,
                                },
                                { destination_user_in => $q,
                                  destination_account_id => $owner->{customer}->id,
                                },
                            ],
                        };
                    }
                },
                second => sub {},
            },

        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallLists/;

sub resource_name{
    return 'calllists';
}

sub dispatch_path{
    return '/api/calllists/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-calllists';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    my $schema = $c->model('DB');
    {

        my $owner = NGCP::Panel::Utils::API::Calllist::get_owner_data($self, $c, $schema);
        last unless $owner;
        $c->stash(owner => $owner); # for query_param: direction
        my $items = $self->item_rs($c);
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        my $href_data = $owner->{subscriber} ?
            "subscriber_id=".$owner->{subscriber}->id :
            "customer_id=".$owner->{customer}->id;
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form, { 'owner' => $owner });
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
