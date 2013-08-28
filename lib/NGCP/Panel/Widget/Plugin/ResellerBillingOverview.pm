package NGCP::Panel::Widget::Plugin::ResellerBillingOverview;
use Moose::Role;
use NGCP::Panel::Utils::DateTime;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/reseller_billing_overview.tt',
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

    my $reseller = $c->model('DB')->resultset('resellers')->find($c->user->reseller_id);
    my $reseller_balance = $reseller->contract->contract_balances->search({
        'start' => { '>=' => $stime },
        'end' => { '<' => $etime},
    })->first;
    my $reseller_sum = 0;
    if($reseller_balance) {
        $reseller_sum = $reseller_balance->cash_balance_interval;
    }

    $c->stash(
        profiles => $reseller->billing_profiles,
        reseller_sum => $reseller_sum,
        customer_sum => $c->model('DB')->resultset('contract_balances')->search_rs({
            'start' => { '>=' => $stime },
            'end' => { '<' => $etime},
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => {
                'contract' => 'contact',
            },
        })->get_column('cash_balance_interval')->sum,
    );
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user_in_realm('reseller') &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
