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

    my $reseller = $c->model('DB')->resultset('resellers')->find($c->user->reseller_id);

    $c->stash(
        domains => $reseller->domain_resellers,
        rwr_sets => $reseller->voip_rewrite_rule_sets,
        sound_sets => $reseller->voip_sound_sets,
    );
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user_in_realm('reseller') &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
