package NGCP::Panel::Controller::API::TimeSets;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::TimeSets/;

use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a collection of (generic) Time Sets, which can each specify a number of ' .
    '(recurring) time-slots, which can be currently used in PeeringRules to select certain peerings.';
}

sub query_params {
    return [
        # {
        #     param => 'reseller_id',
        #     description => 'asdf TODO',
        #     query_type => '',
        # },
        {
            param => 'name',
            description => 'Filter for items matching a B-Number Set name pattern',
            query_type => 'string_like',
        },
    ];
}

sub documentation_sample {
    return  {
        # subscriber_id => 20,
        # name => 'to_austria',
        # bnumbers => [{bnumber => '43*'}],
    };
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $schema = $c->model('DB');
    my $tset;

    try {
        # # no checks, they are in check_resource
        $tset = $schema->resultset('voip_time_sets')->create({
                name => $resource->{name},
                reseller_id => $resource->{reseller_id}, # TODO: create check for valid reseller_id (important)
            });
        for my $t ( @{$resource->{times}} ) {
            $tset->create_related("time_periods", {
                %{ $t }, # TODO: is this safe enough?
            });
        }
    } catch($e) {
        $c->log->error("failed to create timeset: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create timeset.");
        return;
    }

    return $tset;
}

1;

# vim: set tabstop=4 expandtab:
