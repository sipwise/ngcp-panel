package NGCP::Panel::Controller::API::BillingFees;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => ( 
    is => 'ro',
    isa => 'Str',
    default => 
        'Specifies the fees to be applied for a call if it matches the source or destination number of the call.'
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'billing_profile_id',
            description => 'Filter for fees belonging to a specific billing profile',
            query => {
                first => sub {
                    my $q = shift;
                    { billing_profile_id => $q };
                },
                second => sub {},
            },
        },
    ]},
);

with 'NGCP::Panel::Role::API::BillingFees';

class_has('resource_name', is => 'ro', default => 'billingfees');
class_has('dispatch_path', is => 'ro', default => '/api/billingfees/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-billingfees');

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
    action_roles => [qw(HTTPMethods)],
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
        my $fees = $self->item_rs($c);
        (my $total_count, $fees) = $self->paginate_order_collection($c, $fees);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $fee ($fees->all) {
            push @embedded, $self->hal_from_fee($c, $fee, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $fee->id),
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));

        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
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
        my $billing_profile_id = $resource->{billing_profile_id} // undef;

        my $profile;

        # in case of implicit zone declaration (name/detail instead of id),
        # find or create the zone
        if(!defined $resource->{billing_zone_id} &&
           defined $resource->{billing_profile_id} &&
           defined $resource->{billing_zone_zone} &&
           defined $resource->{billing_zone_detail}) {

            $profile = $schema->resultset('billing_profiles')->find($resource->{billing_profile_id});
            if($profile) {
                my $zone = $profile->billing_zones->find({
                    zone => $resource->{billing_zone_zone},
                    detail => $resource->{billing_zone_detail},
                });
                $zone = $profile->billing_zones->create({
                    zone => $resource->{billing_zone_zone},
                    detail => $resource->{billing_zone_detail},
                }) unless $zone;
                $resource->{billing_zone_id} = $zone->id;
                delete $resource->{billing_zone_zone};
                delete $resource->{billing_zone_detail};
            }
        }

        $resource->{billing_zone_id} //= undef;
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        $resource->{billing_profile_id} = $billing_profile_id;

        $profile //= $schema->resultset('billing_profiles')->find($resource->{billing_profile_id});
        unless($profile) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }
        if($c->user->roles ne "admin" && $profile->reseller_id != $reseller_id) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_profile_id'.");
            last;
        }
        my $zone = $profile->billing_zones->find($resource->{billing_zone_id});
        unless($zone) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'billing_zone_id'.");
            last;
        }

        my $fee;
        try {
            $fee = $profile->billing_fees->create($resource);
        } catch($e) {
            $c->log->error("failed to create billing fee: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create billing fee.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $fee->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
