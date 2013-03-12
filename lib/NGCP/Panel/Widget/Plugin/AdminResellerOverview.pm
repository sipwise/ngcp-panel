package NGCP::Panel::Widget::Plugin::AdminResellerOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_reseller_overview.tt'
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    $c->log->debug("AdminResellerOverview::handle");
    return;
};

around filter => sub {
    my ($foo, $self, $c) = @_;

    return $self if(
        $c->check_user_roles(qw/administrator/) &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
};

1;
# vim: set tabstop=4 expandtab:
