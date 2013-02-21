package NGCP::Panel::Widget::Plugin::ResellerOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/reseller_overview.tt'
);

around handle => sub {
    my ($self, $c) = @_;

    print "++++ ResellerOverview::handle\n";
    return;
};

1;
# vim: set tabstop=4 expandtab:
