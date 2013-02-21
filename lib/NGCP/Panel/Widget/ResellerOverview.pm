package NGCP::Panel::Widget::ResellerOverview;
use Moose;

extends 'NGCP::Panel::Widget';

has 'template' => (
    is  => 'ro',
    default => sub { return 'widgets/reseller_overview.tt'; }
);

sub handle {
    my ($c) = @_;
    $c->stash->{resellers} = $c->model->{Provisioning}->resellers->find();
    return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
# vim: set tabstop=4 expandtab:
