package NGCP::Panel::Widget::Dashboard::AdminSystemOverview;
use Moo;

has 'template' => (
    is  => 'ro',
    default => 'widgets/admin_system_overview.tt'
);

sub handle {
    my ($self, $c) = @_;

    $c->log->debug("AdminSystemOverview::handle");
    return;
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'admin'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
