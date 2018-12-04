package NGCP::Panel::Controller::API::BannedIps;


use Sipwise::Base;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::BannedIps/;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Security;

__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines banned ips.';
}

sub get_list{
    my ($self, $c) = @_;
    return NGCP::Panel::Utils::Security::list_banned_ips($c);
}

sub order_by_cols {
    my ($self, $c) = @_;
    my $cols = {
        'ip' => 'ip',
        'id' => 'id',
    };
    return $cols;
}
1;

# vim: set tabstop=4 expandtab:
