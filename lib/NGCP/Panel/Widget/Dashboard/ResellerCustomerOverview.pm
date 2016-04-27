package NGCP::Panel::Widget::Dashboard::ResellerCustomerOverview;
use Moo;

has 'template' => (
    is  => 'ro',
    default => 'widgets/reseller_customer_overview.tt'
);

sub handle {
    my ($self, $c) = @_;

    # add queries used in tt here ...

    return;
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'reseller'
    );
    return;
}

sub _prepare_customers_count {
    my ($self, $c) = @_;

    $c->stash(
        customers => $c->model('DB')->resultset('contracts')->search({
            'me.status' => { '!=' => 'terminated' },
            'contact.reseller_id' => $c->user->reseller_id,
            'product.class' => { 'not in' => [ 'reseller', 'sippeering', 'pstnpeering' ] },
        },{
            join => [ 'contact', { 'billing_mappings' => 'product' } ],
        }),
    );
}

sub _prepare_subscribers_count {
    my ($self, $c) = @_;

    $c->stash(
        subscribers => $c->model('DB')->resultset('voip_subscribers')->search({
            'contact.reseller_id' => $c->user->reseller_id,
            'me.status' => { '!=' => 'terminated' },
        },{
            join => { 'contract' => 'contact'},
        }),
    );
}

sub _prepare_contacts_count {
    my ($self, $c) = @_;

    $c->stash(
        contacts => $c->model('DB')->resultset('contacts')->search({
            reseller_id => $c->user->reseller_id,
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
