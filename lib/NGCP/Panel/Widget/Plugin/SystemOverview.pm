package NGCP::Panel::Widget::Plugin::SystemOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/system_overview.tt'
);

around handle => sub {
    my ($self, $c) = @_;

    print "++++ SystemOverview::handle\n";
    return;
};

1;
# vim: set tabstop=4 expandtab:
