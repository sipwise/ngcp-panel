package NGCP::Panel::Controller::API::PbxDeviceProfiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies a profile to be set in <a href="#pbxdevices">PbxDevices</a>. This item is read-only to subscriberadmins.';
};

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for profiles by name',
            query_type => 'wildcard',
        },
        {
            param => 'config_id',
            description => 'Filter for profiles by config_id',
            query_type => 'wildcard',
        },
    ];
}


use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceProfiles/;

sub resource_name{
    return 'pbxdeviceprofiles';
}

sub dispatch_path{
    return '/api/pbxdeviceprofiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdeviceprofiles';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $field_devs = $self->item_rs($c);

        (my $total_count, $field_devs, my $field_devs_rows) = $self->paginate_order_collection($c, $field_devs);
        my (@embedded, @links);
        for my $dev (@$field_devs_rows) {
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

sub POST :Allow {
    my ($self, $c) = @_;

    if ($c->user->roles eq 'subscriberadmin') {
        $c->log->error("role subscriberadmin cannot create pbxdeviceprofiles");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid role. Cannot create pbxdeviceprofile.");
        return;
    }

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
            'me.id' => $resource->{config_id},
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

1;

# vim: set tabstop=4 expandtab:
