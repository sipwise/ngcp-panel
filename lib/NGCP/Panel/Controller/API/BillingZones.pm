package NGCP::Panel::Controller::API::BillingZones;
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
    return 'Defines zones used to group destinations within <a href="#billingprofiles">Billing Profiles</a>. The zones can be used to group customer\'s calls, like calls within his country or any calls to mobile numbers.';
};

sub query_params {
    return [
        {
            param => 'billing_profile_id',
            description => 'Filter for zones belonging to a specific billing profile',
            query => {
                first => sub {
                    my $q = shift;
                    { billing_profile_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'zone',
            description => 'Filter for zone name',
            query_type => 'wildcard',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::BillingZones/;

sub resource_name{
    return 'billingzones';
}

sub dispatch_path{
    return '/api/billingzones/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingzones';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/billing/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $zones = $self->item_rs($c);
        (my $total_count, $zones, my $zones_rows) = $self->paginate_order_collection($c, $zones);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $zone (@$zones_rows) {
            push @embedded, $self->hal_from_zone($c, $zone, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $zone->id),
            );
        }
        $self->expand_collection_fields($c, \@embedded);
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

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $schema = $c->model('DB');
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $reseller_id;
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $reseller_id = $c->user->reseller_id;
        } else {
            $reseller_id = $c->user->contract->contact->reseller_id;
        }

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $profile = $schema->resultset('billing_profiles')->find($resource->{billing_profile_id});
        unless($profile) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }
        if($c->user->roles ne "admin" && $profile->reseller_id != $reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }

        my $zone;
        try {
            $zone = $profile->billing_zones->create($resource);
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billing zone.", $e);
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_zone = $self->zone_by_id($c, $zone->id);
            return $self->hal_from_zone($c, $_zone, $form); });
        
        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $zone->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
