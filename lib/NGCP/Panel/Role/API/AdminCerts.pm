package NGCP::Panel::Role::API::AdminCerts;

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub item_name {
    return 'admincerts';
}

sub resource_name{
    return 'admincerts';
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Administrator::APICert", $c);
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
