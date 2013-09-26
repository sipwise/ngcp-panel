package NGCP::Panel::Widget::Plugin::SubscriberRegisterOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/subscriber_reg_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 40,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    my $rs = $c->model('DB')->resultset('location')->search({
        username => $c->user->username,
    });
    if($c->config->{features}->{multidomain}) {
        $rs = $rs->search({
            domain => $c->user->domain->domain,
        });
    }
    my $reg_count = $rs->count;
    $rs = $rs->slice(0,4);

    $c->stash(
        regs => $rs,
        reg_count => $reg_count,
    );
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        ($c->user->roles eq 'subscriber' || $c->user->roles eq 'subscriberadmin') &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
