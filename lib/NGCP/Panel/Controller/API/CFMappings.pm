package NGCP::Panel::Controller::API::CFMappings;
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
    return 'Specifies callforward mappings of a subscriber, where multiple mappings can be specified per type (cfu, cfb, cft, cfna, cfs, cfr, cfo) ' .
        'Each mapping consists of a destinationset name (see <a href="#cfdestinationsets">CFDestinationSets</a>), a timeset name ' .
        '(see <a href="#cftimesets">CFTimeSets</a>), a sourceset name (see <a href="#cfsourcesets">CFSourceSets</a>), ' .
        'and a bnumberset name (see <a href="#cfbnumbersets">CFBnumberSets</a>).';
}

sub query_params {
    return [
    ];
}

sub documentation_sample {
    return  {
        cfb => [{
            "destinationset" => "quickset_cfb",
            "timeset" => undef,
            "sourceset" => undef,
        }],
        cfna => [],
        cft => [],
        cft_ringtimeout => "200",
        cfu => [],
        cfs => [],
        cfr => [],
        cfo => [],
    } ;
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFMappings/;

sub resource_name{
    return 'cfmappings';
}

sub dispatch_path{
    return '/api/cfmappings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cfmappings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c); # items is actually a voip_subscribers

        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        for my $subs (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $subs, "cfmappings");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $subs->id),
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
