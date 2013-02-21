package NGCP::Panel::Widget::Plugin::PeeringOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/peering_overview.tt'
);

around handle => sub {
    my ($self, $c) = @_;

    print "++++ PeeringOverview::handle\n";
    return;
};

1;
# vim: set tabstop=4 expandtab:
