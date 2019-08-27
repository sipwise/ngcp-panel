package NGCP::Panel::Controller::API::CFSourceSets;
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
    return 'Defines a collection of CallForward Source Sets, including their source, which can be set '.
        'to define CallForwards using <a href="#cfmappings">CFMappings</a>.',;
}

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for source sets belonging to a specific subscriber',
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
            description => 'Filter for items matching a source set name pattern',
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

sub documentation_sample {
    return  {
        subscriber_id => 20,
        name => 'from_alice',
        sources => [{source => 'alice'}],
    };
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFSourceSets/;

sub resource_name{
    return 'cfsourcesets';
}

sub dispatch_path{
    return '/api/cfsourcesets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cfsourcesets';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $ssets = $self->item_rs($c);

        (my $total_count, $ssets, my $ssets_rows) = $self->paginate_order_collection($c, $ssets);
        my (@embedded, @links);
        for my $sset (@$ssets_rows) {
            push @embedded, $self->hal_from_item($c, $sset, "cfsourcesets");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $sset->id),
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

        my $sset;

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
        if (! exists $resource->{sources} ) {
            $resource->{sources} = [];
        }
        if (ref $resource->{sources} ne "ARRAY") {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'sources'. Must be an array.");
            last;
        }
        try {
            my $domain = $subscriber->domain->domain // '';

            $sset = $schema->resultset('voip_cf_source_sets')->create({
                    name => $resource->{name},
                    mode => $resource->{mode},
                    is_regex => $resource->{is_regex} // 0,
                    subscriber_id => $subscriber->id,
                });
            for my $s ( @{$resource->{sources}} ) {
                $sset->create_related("voip_cf_sources", {
                    source => $s->{source},
                });
            }
        } catch($e) {
            $c->log->error("failed to create cfsourceset: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfsourceset.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_sset = $self->item_by_id($c, $sset->id);
            return $self->hal_from_item($c, $_sset, "cfsourcesets"); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $sset->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
