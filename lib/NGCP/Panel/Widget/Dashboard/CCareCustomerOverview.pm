package NGCP::Panel::Widget::Dashboard::CCareCustomerOverview;

use warnings;
use strict;

sub template {
    return 'widgets/ccare_customer_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if (
        $c->user->roles eq 'ccareadmin' || $c->user->roles eq 'ccare'
    );
    return;
}

sub _prepare_customers_count {
    my ($self, $c) = @_;
    my @product_ids = map { $_->id; } $c->model('DB')->resultset('products')->search_rs({ 'class' => ['sipaccount','pbxaccount'] })->all;
    $c->stash(
        customers => $c->model('DB')->resultset('contracts')->search({
            'me.status' => { '!=' => 'terminated' },
            'product_id' => { -in => [ @product_ids ] },
            ($c->user->roles eq 'ccare'
                ? ('contact.reseller_id' => $c->user->reseller_id)
                : ())
        },{
            join => 'contact',
        }),
    );

}

sub _prepare_subscribers_count {
    my ($self, $c) = @_;

    $c->stash(
        subscribers => $c->model('DB')->resultset('voip_subscribers')->search({
            'me.status' => { '!=' => 'terminated' },
            ($c->user->roles eq 'ccare'
                ? ('contact.reseller_id' => $c->user->reseller_id)
                : ())
        },{
            join => { 'contract' => 'contact'},
        }),
    );
}

sub _prepare_contacts_count {
    my ($self, $c) = @_;

    $c->stash(
        contacts => $c->model('DB')->resultset('contacts')->search({
            'me.status' => { '!=' => 'terminated' },
            ($c->user->roles eq 'ccare'
                ? (reseller_id => $c->user->reseller_id)
                : ())
        }),
    );
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

sub contacts_count {
    my ($self, $c) = @_;
    $self->_prepare_contacts_count($c);
    return $c->stash->{contacts}->count;
}

1;
# vim: set tabstop=4 expandtab:
