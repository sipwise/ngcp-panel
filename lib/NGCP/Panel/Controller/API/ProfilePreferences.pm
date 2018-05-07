package NGCP::Panel::Controller::API::ProfilePreferences;
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
    return 'Specifies certain properties (preferences) for a <a href="#subscriberprofiles">Subscriber Profile</a>. The full list of properties can be obtained via <a href="/api/profilepreferencedefs/">ProfilePreferenceDefs</a>.';
};

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

sub resource_name{
    return 'profilepreferences';
}

sub container_resource_type{
    return 'profiles';
}

sub dispatch_path{
    return '/api/profilepreferences/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-profilepreferences';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $profiles = $self->item_rs($c, "profiles");
        (my $total_count, $profiles) = $self->paginate_order_collection($c, $profiles);
        my (@embedded, @links);
        for my $profile ($profiles->all) {
            push @embedded, $self->hal_from_item($c, $profile, "profiles");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $profile->id),
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
