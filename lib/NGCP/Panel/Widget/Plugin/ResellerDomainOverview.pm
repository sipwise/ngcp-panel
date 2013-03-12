package NGCP::Panel::Widget::Plugin::ResellerDomainOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/reseller_domain_overview.tt'
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    $c->log->debug("ResellerDomainOverview::handle");
    return;
};

around filter => sub {
    my ($foo, $self, $c) = @_;

    return $self if(
        $c->check_user_roles(qw/reseller/) &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
};

1;
# vim: set tabstop=4 expandtab:
