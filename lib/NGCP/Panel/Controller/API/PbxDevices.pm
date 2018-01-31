package NGCP::Panel::Controller::API::PbxDevices;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
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


use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDevices/;

sub resource_name{
    return 'pbxdevices';
}

sub dispatch_path{
    return '/api/pbxdevices/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevices';
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

1;

# vim: set tabstop=4 expandtab:
