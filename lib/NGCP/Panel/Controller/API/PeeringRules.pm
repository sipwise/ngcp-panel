package NGCP::Panel::Controller::API::PeeringRules;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Peering;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines outbound peering rules.';
};

sub query_params {
    return [
        {
            param => 'group_id',
            description => 'Filter for peering group',
            query => {
                first => sub {
                    my $q = shift;
                    { group_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'description',
            description => 'Filter for peering rules description',
            query => {
                first => sub {
                    my $q = shift;
                    { description => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'enabled',
            description => 'Filter for peering rules enabled flag',
            query => {
                first => sub {
                    my $q = shift;
                    { enabled =>  $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PeeringRules/;

sub resource_name{
    return 'peeringrules';
}

sub dispatch_path{
    return '/api/peeringrules/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-peeringrules';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});



sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;
        my $item;
        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        my $dup_item = $c->model('DB')->resultset('voip_peer_rules')->find({
            group_id => $resource->{group_id},
            callee_pattern => $resource->{callee_pattern},
            caller_pattern => $resource->{caller_pattern},
            callee_prefix => $resource->{callee_prefix},
        });
        if($dup_item) {
            $c->log->error("peering rule already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule already exists");
            return;
        }

        try {
            $item = $c->model('DB')->resultset('voip_peer_rules')->create($resource);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
        } catch($e) {
            $c->log->error("failed to create peering rule: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering rule.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
