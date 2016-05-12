package NGCP::Panel::Widget::Dashboard::AdminPeeringOverview;

use warnings;
use strict;

sub template {
    return 'widgets/admin_peering_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'admin'
    );
    return;
}

sub _prepare_peer_groups_count {
    my ($self, $c) = @_;
    my $peer_groups = $c->model('DB')->resultset('voip_peer_groups')->search_rs({});
    $c->stash(
        groups => $peer_groups,
    );
}

sub _prepare_hosts_count {
    my ($self, $c) = @_;
    $self->_prepare_peer_groups_count($c);
    $c->stash(
        hosts => $c->stash->{groups}->search_related_rs('voip_peer_hosts'),
    );
}

sub _prepare_rules_count {
    my ($self, $c) = @_;
    $self->_prepare_peer_groups_count($c);
    $c->stash(
        rules => $c->stash->{groups}->search_related_rs('voip_peer_rules'),
    );
}

sub groups_count {
    my ($self, $c) = @_;
    $self->_prepare_peer_groups_count($c);
    return $c->stash->{groups}->count;
}

sub hosts_count {
    my ($self, $c) = @_;
    $self->_prepare_hosts_count($c);
    return $c->stash->{hosts}->count;
}

sub rules_count {
    my ($self, $c) = @_;
    $self->_prepare_rules_count($c);
    return $c->stash->{rules}->count;
}

1;
# vim: set tabstop=4 expandtab:
