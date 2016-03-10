package NGCP::Panel::Controller::API::PeeringGroups;


use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PeeringGroups/;


use NGCP::Panel::Utils::Peering;


__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines peering groups.';
}

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for peering group name',
            query_type => 'string_like',
        },
        {
            param => 'description',
            description => 'Filter for peering group description',
            query_type => 'string_like',
        },
    ];
}

sub create_item :Private {
    my ($self, $c, $resource, $form) = @_;
    my $item;
    try {
        $item = $c->model('DB')->resultset('voip_peer_groups')->create($resource);
        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
    } catch($e) {
        $c->log->error("failed to create peering group: $e"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering group.");
        last;
    }
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
