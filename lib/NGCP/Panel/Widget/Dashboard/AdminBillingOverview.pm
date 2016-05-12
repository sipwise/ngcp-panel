package NGCP::Panel::Widget::Dashboard::AdminBillingOverview;

use warnings;
use strict;

use NGCP::Panel::Utils::DateTime;

sub template {
    return 'widgets/admin_billing_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'admin'
    );
    return;
}

sub _get_interval {
    my $self = shift;
    my $stime = NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);
    return ($stime,$etime);
}

sub _prepare_profiles_count {
    my ($self, $c) = @_;

    $c->stash(
        profiles => $c->model('DB')->resultset('billing_profiles')->search_rs({
            status => { '!=' => 'terminated'},
            }),
    );

}

sub _prepare_peering_sum {
    my ($self, $c) = @_;

    # how to catchup contract balances of all contracts here?
    # well, we don't care for a stats view ...

    my ($stime,$etime) = $self->_get_interval();
    $c->stash(
        peering_sum => $c->model('DB')->resultset('contract_balances')->search_rs({
            'start' => { '>=' => $stime },
            'end' => { '<' => $etime},
            -exists => $c->model('DB')->resultset('billing_mappings')->search({
                    contract_id => \'= me.contract_id',
                    'product.class' => 'sippeering',
                },{
                    alias => 'myinner',
                    join => 'product',
                })->as_query,
        })->get_column('cash_balance_interval'),
    );
}

sub _prepare_reseller_sum {
    my ($self, $c) = @_;

    # how to catchup contract balances of all contracts here?
    # well, we don't care for a stats view ...

    my ($stime,$etime) = $self->_get_interval();
    $c->stash(
        reseller_sum => $c->model('DB')->resultset('contract_balances')->search_rs({
            'start' => { '>=' => $stime },
            'end' => { '<' => $etime},
            -exists => $c->model('DB')->resultset('billing_mappings')->search({
                    contract_id => \'= me.contract_id',
                    'product.class' => 'reseller',
                },{
                    alias => 'myinner',
                    join => 'product',
                })->as_query,
        })->get_column('cash_balance_interval'),
    );
}

sub _prepare_customer_sum {
    my ($self, $c) = @_;

    # how to catchup contract balances of all contracts here?
    # well, we don't care for a stats view ...

    my ($stime,$etime) = $self->_get_interval();
    $c->stash(
        customer_sum => $c->model('DB')->resultset('contract_balances')->search_rs({
            'start' => { '>=' => $stime },
            'end' => { '<' => $etime},
            -exists => $c->model('DB')->resultset('billing_mappings')->search({
                    contract_id => \'= me.contract_id',
                    'product.class' => 'sipaccount',
                },{
                    alias => 'myinner',
                    join => 'product',
                })->as_query,
        })->get_column('cash_balance_interval'),
    );
}

sub profiles_count {
    my ($self, $c) = @_;

    $self->_prepare_profiles_count($c);
    return $c->stash->{profiles}->count;
}

sub peering_sum {
    my ($self, $c) = @_;

    $self->_prepare_peering_sum($c);
    return $c->stash->{peering_sum}->sum;
}

sub reseller_sum {
    my ($self, $c) = @_;

    $self->_prepare_reseller_sum($c);
    return $c->stash->{reseller_sum}->sum;
}

sub customer_sum {
    my ($self, $c) = @_;

    $self->_prepare_customer_sum($c);
    return $c->stash->{customer_sum}->sum;
}

1;
# vim: set tabstop=4 expandtab:
