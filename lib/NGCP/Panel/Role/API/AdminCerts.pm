package NGCP::Panel::Role::API::AdminCerts;

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);

sub item_name {
    return 'admincerts';
}

sub resource_name{
    return 'admincerts';
}

sub get_form {
    my ($self, $c) = @_;
    require NGCP::Panel::Form::Administrator::APICert;
    return NGCP::Panel::Form::Administrator::APICert->new(c => $c);
}

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs;

    if($c->user->roles eq "admin") {
        $item_rs = $c->model('DB')->resultset('admins');
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $c->model('DB')->resultset('admins')->search({
            reseller_id => $c->user->reseller_id,
        });
    }

    return $item_rs;
}

1;
# vim: set tabstop=4 expandtab:
