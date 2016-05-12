package NGCP::Panel::Widget::Dashboard::ResellerBillingOverview;

use warnings;
use strict;

use NGCP::Panel::Utils::DateTime;

sub template {
    return 'widgets/reseller_billing_overview.tt';
}

sub _get_interval {
    my $self = shift;
    my $stime = NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    return ($stime,$etime);
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'reseller'
    );
    return;
}

sub _get_reseller {
    my ($self, $c) = @_;
    return $c->model('DB')->resultset('resellers')->find($c->user->reseller_id);
}

sub _prepare_reseller_profiles_count {
    my ($self, $c) = @_;
    my $reseller = $self->_get_reseller($c);
    $c->stash(
        profiles => $reseller->billing_profiles,
    );
}

sub _prepare_reseller_balance {
    my ($self, $c) = @_;
    my $reseller = $self->_get_reseller($c);
    my ($stime,$etime) = $self->_get_interval();
    $c->stash(
        balance => $reseller->contract->contract_balances->search({
            'start' => { '>=' => $stime },
            'end' => { '<' => $etime},
        }),
    );
}

sub profiles_count {
    my ($self, $c) = @_;

    $self->_prepare_reseller_profiles_count($c);
    return $c->stash->{profiles}->count;
}

sub reseller_sum {
    my ($self, $c) = @_;
    $self->_prepare_reseller_balance($c);
    my $reseller_balance = $c->stash->{balance}->first;
    my $reseller_sum = 0;
    if($reseller_balance) {
        $reseller_sum = $reseller_balance->cash_balance_interval;
    }
    return $reseller_sum;
}

sub _prepare_customer_sum {
    my ($self, $c) = @_;
    my ($stime,$etime) = $self->_get_interval();

    # how to catchup contract balances of all contracts here?
    # well, we don't care for a stats view ...
    
    $c->stash(
        customer_sum => $c->model('DB')->resultset('contract_balances')->search_rs({
            'start' => { '>=' => $stime },
            'end' => { '<' => $etime},
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => {
                'contract' => 'contact',
            },
        })->get_column('cash_balance_interval'),
    );
}

sub customer_sum {
    my ($self, $c) = @_;
    $self->_prepare_customer_sum($c);
    return $c->stash->{customer_sum}->sum;
}

1;
# vim: set tabstop=4 expandtab:
