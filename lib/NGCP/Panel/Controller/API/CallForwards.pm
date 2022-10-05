package NGCP::Panel::Controller::API::CallForwards;
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
    return 'Specifies basic callforwards of a subscriber, where a number of destinations, times and sources ' .
           ' can be specified for each type (cfu, cfb, cft, cfna, cfs, cfr, cfo). For more complex configurations with ' .
           ' multiple combinations of Timesets, Destinationsets and SourceSets see <a href="#cfmappings">CFMappings</a>.';
};

sub query_params {
    return [ #TODO
    ];
}

sub documentation_sample {
    return {
        cfb => { "destinations" => [{
                    "destination" => "voicebox",
                    "priority" => "1",
                    "timeout" => "300",
                }],
            "times" => [],
            "sources" => [],
        },
        cfna => {},
        cft => { "ringtimeout" => "199" },
        cfu => {},
        cfs => {},
        cfr => {},
        cfo => {},
    };
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallForwards/;

sub resource_name{
    return 'callforwards';
}

sub dispatch_path{
    return '/api/callforwards/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callforwards';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $cfs = $self->item_rs($c, "callforwards");
        (my $total_count, $cfs, my $cfs_rows) = $self->paginate_order_collection($c, $cfs);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $cf (@$cfs_rows) {
            try {
                push @embedded, $self->hal_from_item($c, $cf, $form);
                push @links, Data::HAL::Link->new(
                    relation => 'ngcp:'.$self->resource_name,
                    href     => sprintf('%s%s', $self->dispatch_path, $cf->id),
                );
            }
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
