package NGCP::Panel::Widget::Plugin::AdminResellerOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_reseller_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 10,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    #$self->_prepare_resellers_count($c);
    #$self->_prepare_domains_count($c);
    #$self->_prepare_customers_count($c);
    #$self->_prepare_subscribers_count($c);

    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user->roles eq 'admin' &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

sub _prepare_resellers_count {
    my ($self, $c) = @_;
    $c->stash(
        resellers => $c->model('DB')->resultset('resellers')->search_rs({
            status => { '!=' => 'terminated' },
        }),
    );
}

sub _prepare_domains_count {
    my ($self, $c) = @_;
    $c->stash(
        domains => $c->model('DB')->resultset('domain_resellers')->search_rs({}),
    );
}

sub _prepare_customers_count {
    my ($self, $c) = @_;
    $c->stash(
        customers => $c->model('DB')->resultset('contracts')->search_rs({
            status => { '!=' => 'terminated' },
            'product.class' => { 'not in' => [ 'reseller', 'sippeering', 'pstnpeering' ] },
        }, {
            join => { 'billing_mappings' => 'product' },
        }),
    );
}

sub _prepare_subscribers_count {
    my ($self, $c) = @_;
    $c->stash(
        subscribers => $c->model('DB')->resultset('voip_subscribers')->search_rs({
            status => { '!=' => 'terminated' },
        }),
    );
}

sub resellers_count {
    my ($self, $c) = @_;
    $self->_prepare_resellers_count($c);
    return $c->stash->{resellers}->count;
}

sub domains_count {
    my ($self, $c) = @_;
    $self->_prepare_domains_count($c);
    return $c->stash->{domains}->count;
}

sub customers_count {
    my ($self, $c) = @_;
    $self->_prepare_customers_count($c);
    return $c->stash->{customers}->count;
}

sub subscribers_count {
    my ($self, $c) = @_;
    $self->_prepare_subscribers_count($c);
    return $c->stash->{subscribers}->count;
}

1;
# vim: set tabstop=4 expandtab:
