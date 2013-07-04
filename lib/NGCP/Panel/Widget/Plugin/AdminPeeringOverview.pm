package NGCP::Panel::Widget::Plugin::AdminPeeringOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_peering_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 12,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    my $peer_groups = $c->model('provisioning')->resultset('voip_peer_groups')->search_rs({});
    my $peer_hosts = $peer_groups->search_related_rs('voip_peer_hosts');
    my $peer_rules = $peer_groups->search_related_rs('voip_peer_rules');

    $c->stash(
        groups => $peer_groups,
        hosts => $peer_hosts,
        rules => $peer_rules,
    );

    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user_in_realm('admin') &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
