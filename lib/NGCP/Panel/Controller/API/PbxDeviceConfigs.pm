package NGCP::Panel::Controller::API::PbxDeviceConfigs;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines configs for a <a href="#pbxdevicemodels">PbxDeviceModel</a>. To create or update a config, do a POST or PUT with the proper Content-Type (e.g. text/xml) and pass the properties via query parameters, e.g. <span>/api/pbxdeviceconfigs/?device_id=1&amp;version=1.0</span>';
};

sub query_params {
    return [
        {
            param => 'device_id',
            description => 'Filter for configs of a specific device model',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'device_id' => $q };
                },
                second => sub { },
            },
		},
		{
            param => 'version',
            description => 'Filter for configs by a specific version',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'version' => $q };
                },
                second => sub { },
            },
		},
		{
            param => 'content_type',
            description => 'Filter for configs by a specific content type',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'content_type' => $q };
                },
                second => sub { },
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::PbxDeviceConfigs/;

sub resource_name{
    return 'pbxdeviceconfigs';
}
sub dispatch_path{
    return '/api/pbxdeviceconfigs/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdeviceconfigs';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
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
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
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

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $data = $self->get_valid_raw_post_data(
            c => $c, 
            media_type => [qw#text/plain text/xml#],
        );
        last unless $data;
        my $resource = $c->req->query_params;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [ "device_id" ],
        );

        my $model_rs = $c->model('DB')->resultset('autoprov_devices')->search({ 
            id => $resource->{device_id} 
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $model_rs = $model_rs->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        my $model = $model_rs->first;
        unless($model) {
            $c->log->error("invalid device_id '$$resource{device_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device model does not exist");
            last;
        }

        $resource->{data} = $data;
        $resource->{content_type} = $c->request->header('Content-Type');

        my $item;
        try {
            $item = $model->autoprov_configs->create($resource);
        } catch($e) {
            $c->log->error("failed to create pbxdeviceconfig: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create pbxdeviceconfig.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
