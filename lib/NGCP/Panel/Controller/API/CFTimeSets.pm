package NGCP::Panel::Controller::API::CFTimeSets;
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
            query_type => 'wildcard',
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

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
});

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');

    my $tset;

    if($c->user->roles eq "subscriberadmin" || $c->user->roles eq "subscriber") {
        $resource->{subscriber_id} = $c->user->voip_subscriber->id;
    } elsif(!defined $resource->{subscriber_id}) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Missing mandatory field 'subscriber_id'");
        return;
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
    if (! exists $resource->{times} ) {
        $resource->{times} = [];
    }
    if (ref $resource->{times} ne "ARRAY") {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid field 'times'. Must be an array.");
        return;
    }
    my $times = $resource->{times};
    # enable tz and use_owner_tz params for POST:
    #$times = $self->apply_owner_timezone($c,$b_subscriber,$resource->{times},'deflate');
    try {
        $tset = $schema->resultset('voip_cf_time_sets')->create({
                name => $resource->{name},
                subscriber_id => $subscriber->id,
            });
        for my $t ( @$times ) {
            delete $t->{time_set_id};
            $tset->create_related("voip_cf_periods", $t);
        }
    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create cftimeset.", $e);
        return;
    }

    return $tset;
}

1;

# vim: set tabstop=4 expandtab:
