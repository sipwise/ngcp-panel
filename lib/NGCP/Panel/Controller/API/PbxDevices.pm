package NGCP::Panel::Controller::API::PbxDevices;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DeviceBootstrap;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Specifies a PBX device deployed at a customer.';
};

sub query_params {
    return [
        {
            param => 'customer_id',
            description => 'Search for PBX devices belonging to a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    return { contract_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'profile_id',
            description => 'Search for PBX devices with a specific autoprovisioning device profile',
            query => {
                first => sub {
                    my $q = shift;
                    return { profile_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'identifier',
            description => 'Search for PBX devices matching an identifier/MAC pattern (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    return { identifier => { like => $q } };
                },
                second => sub {},
            },
        }
    ];
}


use parent qw/Catalyst::Controller NGCP::Panel::Role::API::PbxDevices/;

sub resource_name{
    return 'pbxdevices';
}
sub dispatch_path{
    return '/api/pbxdevices/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevices';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

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

        (my $total_count, $field_devs, my $field_devs_rows) = $self->paginate_order_collection($c, $field_devs);
        my (@embedded, @links);
        for my $dev (@$field_devs_rows) {
            push @embedded, $self->hal_from_item($c, $dev);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $dev->id),
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
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

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
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        if ($c->user->roles eq 'subscriberadmin') {
            $resource->{customer_id} = $c->user->account_id;
        }

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $iden_device = $schema->resultset('autoprov_field_devices')->find({identifier => $resource->{identifier}});
        if ($iden_device) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Entry with given 'identifier' already exists.");
            last;
        }
       
        my $customer_rs = $schema->resultset('contracts')->search({
            id => $resource->{customer_id},
            status => { '!=' => 'terminated' },
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $customer_rs = $customer_rs->search({
                'contact.reseller_id' => $c->user->reseller_id,
            }, {
                join => 'contact',
            });
        }
        my $customer = $customer_rs->first;
        unless($customer) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid customer_id, does not exist.");
            last;
        }
        my $dev_model = $self->model_from_profile_id($c, $resource->{profile_id});
        last unless($dev_model);
        
        unless($dev_model->reseller_id == $customer->contact->reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid customer_id and profile_id combination, both must belong to the same reseller.");
            last;
        }

        for my $line ( @{$resource->{lines}} ) {
            unless ($line->{subscriber_id} && $line->{subscriber_id} > 0) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid line. Invalid 'subscriber_id'.");
                return;
            }
            my $b_subs = $schema->resultset('voip_subscribers')->find($line->{subscriber_id});
            my $p_subs = $b_subs ? $b_subs->provisioning_voip_subscriber : undef;
            unless ($b_subs && $b_subs->contract_id == $customer->id) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id. Subscriber doesn't exist or doesn't belong to this customer.");
                return;
            }
            unless ($p_subs) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'. Could not find subscriber.");
                return;
            }
            $line->{subscriber_id} = $p_subs->id;
            unless(defined $line->{linerange}) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid line. Invalid 'linerange'.");
                return;
            }
            my $linerange = $dev_model->autoprov_device_line_ranges->find({
                name => $line->{linerange}
            });
            unless($linerange) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'linerange', does not exist.");
                return;
            }
            delete $line->{linerange};
            $line->{linerange_id} = $linerange->id;
            if($line->{key_num} >= $linerange->num_lines) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'key_num', out of range for this linerange.");
                return;
            }

            $line->{line_type} = delete $line->{type};
        }

        my $device;

        try {
            $device = $schema->resultset('autoprov_field_devices')->create({
                    profile_id => $resource->{profile_id},
                    contract_id => $customer->id,
                    identifier => $resource->{identifier},
                    station_name => $resource->{station_name},
                });
            if($dev_model->bootstrap_method eq "redirect_yealink") {
                my @chars = ("A".."Z", "a".."z", "0".."9");
                my $device_key = "";
                $device_key .= $chars[rand @chars] for 0 .. 15;
                $device->update({ encryption_key => $device_key });
            }
            my $err = NGCP::Panel::Utils::DeviceBootstrap::dispatch($c, 'register', $device);
            die $err if($err);
            for my $line ( @{$resource->{lines}} ) {
                $device->autoprov_field_device_lines->create($line);
            }
        } catch($e) {
            $c->log->error("failed to create pbxdevice: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create pbxdevice.");
            last;
        };

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $device->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
