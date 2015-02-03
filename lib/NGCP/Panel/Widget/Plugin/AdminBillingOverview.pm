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
    my $stime = NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1);

    $c->stash(
        profiles => $c->model('DB')->resultset('billing_profiles')->search_rs({
            status => { '!=' => 'terminated'},
            }),
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
        })->get_column('cash_balance_interval')->sum,
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
        })->get_column('cash_balance_interval')->sum,
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
        })->get_column('cash_balance_interval')->sum,
    );
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

1;
# vim: set tabstop=4 expandtab:
