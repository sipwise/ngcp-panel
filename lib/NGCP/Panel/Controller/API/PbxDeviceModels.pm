package NGCP::Panel::Controller::API::PbxDeviceModels;
use Sipwise::Base;
use namespace::sweep;
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
        'Specifies a model to be set in <a href="#pbxdeviceconfigs">PbxDeviceConfigs</a>.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'reseller_id',
            description => 'Filter for models belonging to a certain reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'model',
            description => 'Filter for models matching a model name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { model => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'vendor',
            description => 'Filter for models matching a vendor name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { vendor => { like => $q } };
                },
                second => sub {},
            },
        },
    ]},
);


with 'NGCP::Panel::Role::API::PbxDeviceModels';

class_has('resource_name', is => 'ro', default => 'pbxdevicemodels');
class_has('dispatch_path', is => 'ro', default => '/api/pbxdevicemodels/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodels');

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
    my $allowed_methods = $self->allowed_methods;
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

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
        unless($reseller) {
            $c->log->error("invalid reseller_id '$$resource{reseller_id}', does not exist");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller_id, does not exist");
            last;
        }

        my $item;
        $item = $c->model('DB')->resultset('autoprov_devices')->find({
            reseller_id => $resource->{reseller_id},
            vendor => $resource->{vendor},
            model => $resource->{model},
        });
        if($item) {
            $c->log->error("device model with vendor '$$resource{vendor}' and model '$$resource{model}'already exists for reseller_id '$$resource{reseller_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Device model already exists for this reseller");
            last;
        }

        my $linerange = delete $resource->{linerange};
        unless(ref $linerange eq "ARRAY") {
            $c->log->error("linerange must be array");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange parameter, must be array");
            last;
        }


        try {
            $item = $c->model('DB')->resultset('autoprov_devices')->create($resource);
            foreach my $range(@{ $linerange }) {
                unless(ref $range eq "HASH") {
                    use Data::Dumper;
                    $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
                    return;
                }
                $item->autoprov_device_line_ranges->create($range);
            }
        } catch($e) {
            $c->log->error("failed to create device model: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create device model.");
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
