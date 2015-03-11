package NGCP::Panel::Controller::API::PbxDeviceProfiles;
use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Specifies a profile to be set in <a href="#pbxdevices">PbxDevices</a>.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'name',
            description => 'Filter for profiles matching a name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'config_id',
            description => 'Filter for profiles matching a config_id',
            query => {
                first => sub {
                    my $q = shift;
                    { 'config_id' => { like => $q } };
                },
                second => sub {},
            },
        },
    ]},
);


with 'NGCP::Panel::Role::API::PbxDeviceProfiles';

class_has('resource_name', is => 'ro', default => 'pbxdeviceprofiles');
class_has('dispatch_path', is => 'ro', default => '/api/pbxdeviceprofiles/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-pbxdeviceprofiles');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(HTTPMethods)],
);

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
    {
        my $field_devs = $self->item_rs($c);

        (my $total_count, $field_devs) = $self->paginate_order_collection($c, $field_devs);
        my (@embedded, @links);
        for my $dev ($field_devs->all) {
            push @embedded, $self->hal_from_item($c, $dev);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $dev->id),
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

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $item;
        $item = $c->model('DB')->resultset('autoprov_profiles')->find({
            config_id => $resource->{config_id},
            name => $resource->{name},
        });
        if($item) {
            $c->log->error("Pbx device profile with name '$$resource{name}' already exists for config_id '$$resource{config_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device profile with this name already exists for this config");
            last;
        }
        my $config_rs = $c->model('DB')->resultset('autoprov_configs')->search({
            id => $resource->{config_id},
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $config_rs = $config_rs->search({
                'device.reseller_id' => $c->user->reseller_id,
            },{
                join => 'device',
            });
        }
        my $config = $config_rs->first;
        unless($config) {
            $c->log->error("Pbx device config with confg_id '$$resource{config_id}' does not exist");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device config does not exist");
            last;
        }

        try {
            $item = $config->autoprov_profiles->create($resource);
        } catch($e) {
            $c->log->error("failed to create pbx device profile: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create pbx device profile.");
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
    return 1;
}

# vim: set tabstop=4 expandtab:
