package NGCP::Panel::Widget::Plugin::ResellerDomainOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/reseller_domain_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 10,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    # add queries used in tt here ...

    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user->roles eq 'reseller' &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

sub _get_reseller {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('resellers')->find($c->user->reseller_id);
}

sub _prepare_domains_count {
    my ($self, $c) = @_;
    my $reseller = $self->_get_reseller($c);
    $c->stash(
        domains => $reseller->domain_resellers,
    );
}

sub _prepare_rwr_sets_count {
    my ($self, $c) = @_;
    my $reseller = $self->_get_reseller($c);
    $c->stash(
        rwr_sets => $reseller->voip_rewrite_rule_sets,
    );
}

sub _prepare_sound_sets_count {
    my ($self, $c) = @_;
    my $reseller = $self->_get_reseller($c);
    $c->stash(
        sound_sets => $reseller->voip_sound_sets,
    );
}

sub domains_count {
    my ($self, $c) = @_;
    $self->_prepare_domains_count($c);
    return $c->stash->{domains}->count;
}

sub rwr_sets_count {
    my ($self, $c) = @_;
    $self->_prepare_rwr_sets_count($c);
    return $c->stash->{rwr_sets}->count;
}

sub sound_sets_count {
    my ($self, $c) = @_;
    $self->_prepare_sound_sets_count($c);
    return $c->stash->{sound_sets}->count;
}

1;
# vim: set tabstop=4 expandtab:
