package NGCP::Panel::Widget::Plugin::AdminBillingOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_billing_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 11,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    $c->log->debug("AdminBillingOverview::handle");
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    use Data::Printer; p $c->user;
    return $self if(
        $type eq $self->type &&
        $c->user_in_realm('admin') &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
