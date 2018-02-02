package NGCP::Panel::Controller::API::CFDestinationSets;
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
    return 'Defines a collection of CallForward Destination Sets, including their destination, which can be set '.
        'to define CallForwards using <a href="#cfmappings">CFMappings</a>.',;
}

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for destination sets belonging to a specific subscriber',
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
            description => 'Filter for contacts matching a destination set name pattern',
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


use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CFDestinationSets/;

sub resource_name{
    return 'cfdestinationsets';
}

sub dispatch_path{
    return '/api/cfdestinationsets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cfdestinationsets';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $dsets = $self->item_rs($c);

        (my $total_count, $dsets) = $self->paginate_order_collection($c, $dsets);
        my (@embedded, @links);
        for my $dset ($dsets->all) {
            push @embedded, $self->hal_from_item($c, $dset, "cfdestinationsets");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $dset->id),
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

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $dset;

        if($c->user->roles eq "subscriberadmin") {
            $resource->{subscriber_id} //= $c->user->voip_subscriber->id;
        } elsif($c->user->roles eq "subscriber") {
            $resource->{subscriber_id} = $c->user->voip_subscriber->id;
        }

        my $b_subscriber = $schema->resultset('voip_subscribers')->find({
                id => $resource->{subscriber_id},
            });
        unless($b_subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'subscriber_id'.");
            last;
        }
        #if($c->user->roles eq "subscriberadmin" &&
        #   $b_subscriber->contract_id != $c->user->account_id) {
        #    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        #    last;
        #}

        my $subscriber = $b_subscriber->provisioning_voip_subscriber;
        unless($subscriber) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
            last;
        }
        if (! exists $resource->{destinations} ) {
            $resource->{destinations} = [];
        }
        if (!$self->check_destinations($c, $resource)) {
            last;
        }
        try {
            my $primary_nr_rs = $b_subscriber->primary_number;
            my $number;
            if ($primary_nr_rs) {
                $number = $primary_nr_rs->cc . ($primary_nr_rs->ac //'') . $primary_nr_rs->sn;
            } else {
                $number = ''
            }
            my $domain = $subscriber->domain->domain // '';

            $dset = $schema->resultset('voip_cf_destination_sets')->create({
                    name => $resource->{name},
                    subscriber_id => $subscriber->id,
                });
            for my $d ( @{$resource->{destinations}} ) {
                delete $d->{destination_set_id};
                delete $d->{simple_destination};
                $d->{destination} = NGCP::Panel::Utils::Subscriber::field_to_destination(
                        destination => $d->{destination},
                        number => $number,
                        domain => $domain,
                        uri => $d->{destination},
                    );
                $dset->create_related("voip_cf_destinations", $d);
            }
        } catch($e) {
            $c->log->error("failed to create cfdestinationset: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfdestinationset.");
            last;
        }

        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_dset = $self->item_by_id($c, $dset->id);
            return $self->hal_from_item($c, $_dset, "cfdestinationsets"); });
        
        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $dset->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
