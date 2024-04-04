package NGCP::Panel::Controller::API::CFDestinationSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::CallForwards qw();

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
            query_type => 'wildcard',
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
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');

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
        return;
    }

    my $subscriber = $b_subscriber->provisioning_voip_subscriber;
    unless($subscriber) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid subscriber.");
        return;
    }
    if (! exists $resource->{destinations} ) {
        $resource->{destinations} = [];
    }

    if (!NGCP::Panel::Utils::CallForwards::check_destinations(
        c => $c,
        resource => $resource,
        err_code => sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        },
    )) {
        return;
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
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cfdestinationset.", $e);
        return;
    }

    return $dset;
}

1;

# vim: set tabstop=4 expandtab:
