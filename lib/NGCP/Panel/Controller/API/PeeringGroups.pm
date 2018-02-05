package NGCP::Panel::Controller::API::PeeringGroups;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
#
use NGCP::Panel::Utils::Peering;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PeeringGroups/;#Catalyst::Controller

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines peering groups.';
};

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for peering group name',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'description',
            description => 'Filter for peering group description',
            query => {
                first => sub {
                    my $q = shift;
                    { description => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
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

        my $form = $self->get_form($c);
        
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        $resource = $form->custom_get_values;
        last unless $resource;
        my $item;
        my $dup_item = $c->model('DB')->resultset('voip_peer_groups')->find({
            name => $resource->{name},
        });
        if($dup_item) {
            $c->log->error("peering group with name '$$resource{name}' already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering group with this name already exists");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('voip_peer_groups')->create($resource);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
        } catch($e){
            $c->log->error("failed to create peering group: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering group.");
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
