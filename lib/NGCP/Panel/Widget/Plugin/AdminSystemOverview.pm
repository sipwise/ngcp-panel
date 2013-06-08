package NGCP::Panel::Widget::Plugin::AdminSystemOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_system_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 1,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    $c->log->debug("AdminSystemOverview::handle");
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
