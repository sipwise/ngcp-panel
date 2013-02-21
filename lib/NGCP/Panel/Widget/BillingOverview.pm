package NGCP::Panel::Widget::BillingOverview;
use Moose;

extends 'NGCP::Panel::Widget';

has 'template' => (
    is  => 'ro',
    default => sub { return 'widgets/billing_overview.tt'; }
);

sub handle {
    my ($c) = @_;
    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
