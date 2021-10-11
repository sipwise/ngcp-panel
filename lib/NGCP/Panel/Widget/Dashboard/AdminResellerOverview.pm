package NGCP::Panel::Widget::Dashboard::AdminResellerOverview;

use warnings;
use strict;
use NGCP::Panel::Utils::DateTime qw();

sub template {
    return 'widgets/admin_reseller_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'admin'
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
        domains => $c->model('DB')->resultset('domains')->search_rs({}),
    );
}

sub _prepare_customers_count {
    my ($self, $c) = @_;
    $c->stash(
        customers => $c->model('DB')->resultset('contracts')->search({
            'me.status' => { '!=' => 'terminated' },
            'contact.reseller_id' => { '-not' => undef },
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            'join' => [ 'contact', 'product' ],
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
