package NGCP::Panel::Widget::Plugin::AdminBillingOverview;
use Moose::Role;
use NGCP::Panel::Utils::DateTime;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/admin_billing_overview.tt'
);

has 'type' => (
    is  => 'ro',
    isa => 'Str',
    default => 'dashboard_widgets',
);

has 'priority' => (
    is  => 'ro',
    isa => 'Int',
    default => 11,
);

around handle => sub {
    my ($foo, $self, $c) = @_;

    #how to catchup contract balances of all contracts here? well, irrelevant for a stats view ...
    #$self->_prepare_profiles_count($c);
    #$self->_prepare_peering_sum($c);
    #$self->_prepare_reseller_sum($c);
    #$self->_prepare_customer_sum($c);
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
        })->get_column('cash_balance_interval'), #->sum,
    );
}

sub _prepare_reseller_sum {
    my ($self, $c) = @_;

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
        })->get_column('cash_balance_interval'), #->sum,
    );
}

sub _prepare_customer_sum {
    my ($self, $c) = @_;

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
        })->get_column('cash_balance_interval'), #->sum,
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
