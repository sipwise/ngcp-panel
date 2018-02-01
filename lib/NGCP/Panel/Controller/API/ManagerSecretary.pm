package NGCP::Panel::Controller::API::ManagerSecretary;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;
use Data::Dumper;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'API Control for manager secretary call forwardings';
};

sub query_params {
    return [
    ];
}

sub documentation_sample {
    return {
    };
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::ManagerSecretary/;

sub resource_name{
    return 'managersecretary';
}

sub dispatch_path{
    return '/api/managersecretary/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-managersecretary';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $preference = $self->require_preference($c);

        my $cfs = $self->item_rs($c, "managersecretary");
        (my $total_count, $cfs) = $self->paginate_order_collection($c, $cfs);

        if ($preference && $preference eq 'internal') {
            my @items = ();
            foreach my $item ($cfs->all) {
                push @items, $self->resource_from_item($c, $item);
            }
            $c->response->status(HTTP_OK);
            $c->response->header(Preference_Applied => 'return=internal');
            $c->response->body(JSON::to_json(\@items));
            return;
        }

        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $cf ($cfs->all) {
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page - 1, $rows));
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

1;

# vim: set tabstop=4 expandtab:
