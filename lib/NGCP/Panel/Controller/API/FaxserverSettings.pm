package NGCP::Panel::Controller::API::FaxserverSettings;
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

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies faxserver settings for a specific subscriber.';
};

sub query_params {
    return [
        {
            param => 'name_or_password',
            description => 'Filter for items (subscribers) where name or password field match given pattern',
            query => {
                first => sub {
                    my $q = shift;
                    return { '-or' => [
                            { 'voip_fax_preference.name' => { like => $q } },
                            { 'voip_fax_preference.password' => { like => $q } },
                        ] };
                },
                second => sub {
                    return { prefetch => { 'provisioning_voip_subscriber' => 'voip_fax_preference' } };
                },
            },
        },
        {
            param => 'active',
            description => 'Filter for items (subscribers) with active faxserver settings',
            query => {
                first => sub {
                    my $q = shift;
                    if ($q) {
                        { 'voip_fax_preference.active' => 1 };
                    } else {
                        {};
                    }
                },
                second => sub {
                    { prefetch => { 'provisioning_voip_subscriber' => 'voip_fax_preference' } };
                },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::FaxserverSettings/;

sub resource_name{
    return 'faxserversettings';
}
sub dispatch_path{
    return '/api/faxserversettings/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-faxserversettings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});





sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $cfs = $self->item_rs($c);
        (my $total_count, $cfs) = $self->paginate_order_collection($c, $cfs);
        my (@embedded, @links);
        for my $cf ($cfs->all) {
            try {
                push @embedded, $self->hal_from_item($c, $cf);
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
