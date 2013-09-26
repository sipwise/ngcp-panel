package NGCP::Panel::Widget::Plugin::ResellerCustomerOverview;
use Moose::Role;

has 'template' => (
    is  => 'ro',
    isa => 'Str',
    default => 'widgets/reseller_customer_overview.tt'
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

    my $reseller = $c->model('DB')->resultset('resellers')->find($c->user->reseller_id);

    $c->stash(
        customers => $c->model('DB')->resultset('contracts')->search({
            'me.status' => { '!=' => 'terminated' },
            'contact.reseller_id' => $c->user->reseller_id,
            'product.class' => { 'not in' => [ 'reseller', 'sippeering', 'pstnpeering' ] },
        },{
            join => [ 'contact', { 'billing_mappings' => 'product' } ],
        }),
        subscribers => $c->model('DB')->resultset('voip_subscribers')->search({
            'contact.reseller_id' => $c->user->reseller_id,
            'me.status' => { '!=' => 'terminated' },
        },{
            join => { 'contract' => 'contact'},
        }),
        contacts => $c->model('DB')->resultset('contacts')->search({
            reseller_id => $c->user->reseller_id,
        }),
    );
    return;
};

sub filter {
    my ($self, $c, $type) = @_;

    return $self if(
        $type eq $self->type &&
        $c->user->roles eq 'reseller' &&
        ref $c->controller eq 'NGCP::Panel::Controller::Dashboard'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
