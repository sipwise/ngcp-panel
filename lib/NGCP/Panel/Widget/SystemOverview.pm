package NGCP::Panel::Widget::SystemOverview;
use Moose;

extends 'NGCP::Panel::Widget';

has 'template' => (
    is  => 'ro',
    default => sub { return 'widgets/system_overview.tt'; }
);

sub handle {
    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
