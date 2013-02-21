package NGCP::Panel::Widget::Plugin::BillingOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/billing_overview.tt'
);

around handle => sub {
    my ($self, $c) = @_;

    print "++++ BillingOverview::handle\n";
    return;
};

1;
# vim: set tabstop=4 expandtab:
