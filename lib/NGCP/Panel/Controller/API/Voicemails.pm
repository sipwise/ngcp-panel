package NGCP::Panel::Controller::API::Voicemails;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines the meta information like duration, callerid etc for voicemail recordings. The actual recordings can be fetched via the <a href="#voicemailrecordings">VoicemailRecordings</a> relation.';
};

sub query_params {
    return [
        {
            param => 'tz',
            description => 'Format timestamp according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
        {
            param => 'use_owner_tz',
            description => 'Format timestamp according to the filtered customer\'s/subscribers\'s inherited time zone.',
        },
        {
            param => 'subscriber_id',
            description => 'Filter for voicemails belonging to a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    # join is already done in get_item_rs
                    { 'voip_subscriber.id' => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'folder',
            description => 'Filter for voicemails in a specific folder (one of INBOX, Old, Friends, Family, Cust1 to Cust4)',
            query => {
                first => sub {
                    my $q = shift;
                    # join is already done in get_item_rs
                    { 'me.dir' => { like => '%/'.$q } };
                },
                second => sub { },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Voicemails/;

sub resource_name{
    return 'voicemails';
}

sub dispatch_path{
    return '/api/voicemails/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-voicemails';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->get_list($c);
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item);
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
