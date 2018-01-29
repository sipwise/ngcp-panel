package NGCP::Panel::Controller::API::CFTimeSets;
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
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of CallForward Time Sets, including their times (periods), which can be set '.
        'to define CallForwards using <a href="#cfmappings">CFMappings</a>.';
}

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for timesets belonging to a specific subscriber',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'voip_subscriber.id' => $q };
                },
                second => sub {
                    return { join => {subscriber => 'voip_subscriber'}};
                },
            },
        },
        {
            param => 'name',
            description => 'Filter for contacts matching a timeset name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}


use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFTimeSets/;

sub resource_name{
    return 'cftimesets';
}
sub dispatch_path{
    return '/api/cftimesets/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cftimesets';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
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



sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $timesets = $self->item_rs($c);

        (my $total_count, $timesets) = $self->paginate_order_collection($c, $timesets);
        my (@embedded, @links);
        for my $tset ($timesets->all) {
            push @embedded, $self->hal_from_item($c, $tset, "cftimesets");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $tset->id),
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

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $tset;

        if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
            $resource->{subscriber_id} = $c->user->voip_subscriber->id;
        } elsif(!defined $resource->{subscriber_id}) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'subscriber_id'");
            last;
        }
        my $b_subscriber = $schema->resultset('voip_subscribers')->find({
                id => $resource->{subscriber_id},
            });
        unless($b_subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
            last;
        }
        my $subscriber = $b_subscriber->provisioning_voip_subscriber;
        unless($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
            last;
        }
        if (! exists $resource->{times} ) {
            $resource->{times} = [];
        }
        if (ref $resource->{times} ne "ARRAY") {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'times'. Must be an array.");
            last;
        }
        try {
            $tset = $schema->resultset('voip_cf_time_sets')->create({
                    name => $resource->{name},
                    subscriber_id => $subscriber->id,
                });
            for my $t ( @{$resource->{times}} ) {
                delete $t->{time_set_id};
                $tset->create_related("voip_cf_periods", $t);
            }
        } catch($e) {
            $c->log->error("failed to create cftimeset: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cftimeset.");
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_dset = $self->item_by_id($c, $tset->id);
            return $self->hal_from_item($c, $_dset, "cftimesets"); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $tset->id));
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
